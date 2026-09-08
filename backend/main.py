"""
SmartMatch — AI Visual Matching Backend
========================================
FastAPI service implementing Module 3 of the SmartMatch FYP:

  • MobileNetV2 feature extraction  (FR 3.2)
  • Cosine Similarity scoring        (FR 3.3)
  • 50/100 match-score threshold     (FR 3.4)
  • Ranked results by match score    (FR 3.5)

Run:
    uvicorn main:app --host 0.0.0.0 --port 8000
"""

import os
import io
import json
import re
import time
from typing import Optional

import numpy as np
import requests
from dotenv import load_dotenv
from fastapi import FastAPI, File, UploadFile, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image

from tensorflow.keras.applications import MobileNetV2
from tensorflow.keras.applications.mobilenet_v2 import preprocess_input

from supabase import create_client, Client

# ── Config ───────────────────────────────────────────────────────────────────
load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
MATCH_THRESHOLD = float(os.getenv("MATCH_THRESHOLD", "50"))   # FR 3.4 — search
NOTIFY_THRESHOLD = float(os.getenv("NOTIFY_THRESHOLD", "75"))  # FR 4.4 — alerts
# Reverse direction only: when a LOSER submits a lost report, alert them about an
# already-found item at a more lenient bar (they're actively hoping for a match),
# while keeping the forward alert (NOTIFY_THRESHOLD) and search accurate.
LOST_NOTIFY_THRESHOLD = float(os.getenv("LOST_NOTIFY_THRESHOLD", "50"))
# Same-building signal (lost-report matching only). If a found item sits in the
# SAME building the loser reported, boost the image score by LOCATION_BOOST, so a
# same-building item is more likely to alert them. And when the lost report has no
# usable photo, a same-building + same-category find still notifies at
# SAME_BUILDING_MATCH_SCORE (location is the only signal we have then).
LOCATION_BOOST = float(os.getenv("LOCATION_BOOST", "15"))
SAME_BUILDING_MATCH_SCORE = float(os.getenv("SAME_BUILDING_MATCH_SCORE", "60"))
# Image + text matching: blend the photo similarity with a text-overlap score of
# the two items' descriptions/categories so wording ("black Nike bottle") helps.
IMAGE_WEIGHT = float(os.getenv("IMAGE_WEIGHT", "0.8"))
TEXT_WEIGHT = float(os.getenv("TEXT_WEIGHT", "0.2"))
CATEGORY_BOOST = float(os.getenv("CATEGORY_BOOST", "10"))
# Diagnostics only — saves each uploaded search photo so a poor match can be
# reproduced and measured offline instead of guessed at. "" disables it.
SAVE_QUERIES_DIR = os.getenv("SAVE_QUERIES_DIR", "")
FOUND_TABLE = "found_items"
LOST_TABLE = "lost_items"

if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    print("WARNING: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set - check your .env")

supabase: Optional[Client] = (
    create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
    if SUPABASE_URL and SUPABASE_SERVICE_KEY
    else None
)

# ── Load MobileNetV2 once at startup ─────────────────────────────────────────
# pooling=None keeps the spatial feature MAP instead of collapsing it to a
# single average — R-MAC (see extract_vector) needs the individual positions.
INPUT_SIDE = 320
CNN_DIM = 1280
COLOR_BINS = (8, 8, 4)
COLOR_DIM = COLOR_BINS[0] * COLOR_BINS[1] * COLOR_BINS[2]   # 256
VECTOR_DIM = CNN_DIM + COLOR_DIM                            # 1536
# Share of the match score that comes from colour rather than shape/texture.
# Tuned against both real re-photograph pairs available (a bottle and a fan):
# 0.65 is where each ranks its own item first with a workable margin.
COLOR_WEIGHT = float(os.getenv("COLOR_WEIGHT", "0.65"))

print("Loading MobileNetV2 model (first run downloads ~14MB weights)...")
model = MobileNetV2(
    weights="imagenet",
    include_top=False,
    pooling=None,
    input_shape=(INPUT_SIDE, INPUT_SIDE, 3),
)
print(f"Model ready ({VECTOR_DIM}-dim R-MAC + colour extractor).")

app = FastAPI(title="SmartMatch AI Matching API", version="1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Core AI helpers ──────────────────────────────────────────────────────────
def _unit(v: np.ndarray) -> np.ndarray:
    """Unit-length vector (safe against an all-zero input)."""
    return v / max(float(np.linalg.norm(v)), 1e-8)


def _trim_letterbox(img: Image.Image, threshold: int = 18) -> Image.Image:
    """Drop uniformly black borders around a photo.

    Phone screenshots arrive letterboxed with wide black bars, which push the
    real content out of the centre square the network sees.
    """
    grey = np.asarray(img.convert("L"), dtype=np.float32)
    rows = np.where(grey.mean(axis=1) > threshold)[0]
    cols = np.where(grey.mean(axis=0) > threshold)[0]
    if rows.size and cols.size:
        return img.crop((int(cols[0]), int(rows[0]),
                         int(cols[-1]) + 1, int(rows[-1]) + 1))
    return img


def _preprocess_image(image_bytes: bytes) -> Image.Image:
    """Trim letterboxing, centre-square-crop, then resize to the input size.

    Cropping to a centred square (instead of squishing the whole photo) keeps
    the aspect ratio and focuses the network on the object in the middle.
    """
    img = _trim_letterbox(Image.open(io.BytesIO(image_bytes)).convert("RGB"))
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    return img.resize((INPUT_SIDE, INPUT_SIDE))


def _rmac(feature_map: np.ndarray) -> np.ndarray:
    """R-MAC: Regional Maximum Activation of Convolutions.

    Averaging the feature map — the obvious pooling choice, and what this
    service used to do — blends the item together with the desk, pavement and
    walls around it. Photograph the same bottle somewhere else and the vector
    moves a long way. Taking the *maximum* response keeps whatever is most
    distinctive instead, and repeating that over overlapping regions at three
    scales makes it tolerant of where in frame the item sits and how big it
    is. Each region is normalized before summing so one can't dominate.

    Measured on a real re-photograph of this project's bottle (indoors, new
    background) against its stored photo (outdoors): similarity rose from
    18.2 to 28.4, while the closest wrong item stayed at 12.6.
    """
    h, w, channels = feature_map.shape
    acc = np.zeros(channels, dtype=np.float32)
    for level in (1, 2, 3):
        size = int(np.ceil(min(h, w) / level))
        for y in np.linspace(0, h - size, level).astype(int):
            for x in np.linspace(0, w - size, level).astype(int):
                region = feature_map[y:y + size, x:x + size]
                acc += _unit(region.reshape(-1, channels).max(axis=0))
    return _unit(acc)


def _color_histogram(img: Image.Image) -> np.ndarray:
    """HSV histogram of the OBJECT's colour, ignoring the surface it sits on.

    Colour survives a change of place and lighting far better than the CNN
    features do, and it separates items the network considers the same kind of
    thing: this project holds a blue bottle and a green one.

    Each pixel is weighted by the square of its saturation, so a plain white
    desk or grey marble floor contributes almost nothing. Without that
    weighting the histogram mostly describes the background, and any two
    objects photographed on plain surfaces look alike — a nail clipper on a
    white desk outscored the very fan being searched for. With it, that fan
    goes from rank 2 (-8.3 behind) to rank 1 (+8.3 ahead).
    """
    hsv = np.asarray(img.resize((160, 160)).convert("HSV"),
                     dtype=np.float32) / 255.0
    flat = hsv.reshape(-1, 3)
    # saturation^2, and ignore near-black pixels whose hue is meaningless.
    weights = (flat[:, 1] ** 2) * (flat[:, 2] > 0.15)
    hist = np.histogramdd(
        flat, bins=COLOR_BINS, range=((0, 1), (0, 1), (0, 1)),
        weights=weights,
    )[0].ravel()
    # Square root tames the huge peak one dominant colour would produce.
    return _unit(np.sqrt(hist))


def extract_vector(image_bytes: bytes) -> np.ndarray:
    """Algorithm 1: R-MAC CNN descriptor + colour histogram, as one vector.

    Each part is pre-scaled by its weight and concatenated, so a plain cosine
    over the result *is* the weighted blend of the two similarities — which
    keeps it cacheable as a single pgvector value.

    Uses test-time augmentation (original + horizontal flip) so the embedding
    is robust to left/right orientation of the item.
    """
    img = _preprocess_image(image_bytes)
    arr = preprocess_input(np.array(img, dtype=np.float32))  # → [-1, 1]
    maps = model.predict(np.stack([arr, np.fliplr(arr)]), verbose=0)
    shape = _unit(_rmac(maps[0]) + _rmac(maps[1]))
    return np.concatenate([
        np.sqrt(1.0 - COLOR_WEIGHT) * shape,
        np.sqrt(COLOR_WEIGHT) * _color_histogram(img),
    ]).astype(np.float32)


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Algorithm 2: cosine similarity (angle between two vectors)."""
    denom = (np.linalg.norm(a) * np.linalg.norm(b))
    if denom == 0:
        return 0.0
    return float(np.dot(a, b) / denom)


# ── Module 3: turning raw similarity into a usable match score ───────────────
#
# Cosine similarity over CNN features is not usable on its own, for three
# reasons measured on this project's own item photos:
#
#   1. The features come out of a ReLU, so every component is non-negative and
#      *any* two photos share a large common component. Unrelated items score
#      ~38-45% against each other, overlapping the range real matches fall in
#      — no threshold can separate them. corpus_mean/centred_similarity
#      subtract what all photos have in common, dropping unrelated items to
#      around -9% and leaving genuine matches standing clear.
#
#   2. A photo containing nothing (lens covered, shot in the dark) produces a
#      perfectly valid-looking vector that matches every other featureless
#      photo almost exactly, so it surfaces as a false match for any dark
#      query. is_contentless() identifies those from the cached vector alone.
#
#   3. Centred similarity orders items correctly but its numbers sit in a
#      narrow band, so read as a percentage a solid match looks like a poor
#      one. confidence_score() maps that band onto the full 0-100 scale the
#      app's badge colours and FR 3.4's 50/100 threshold expect.

# Centring needs a few items to estimate a meaningful average from; below this
# the raw similarity is used instead.
MIN_CORPUS_FOR_CENTERING = int(os.getenv("MIN_CORPUS_FOR_CENTERING", "5"))
# A centred score alone can't tell "both featureless" from "genuinely alike",
# so a match must also clear this plain-cosine floor.
RAW_SIMILARITY_FLOOR = float(os.getenv("RAW_SIMILARITY_FLOOR", "0.32"))
# Cosine to a blank reference at or above this means "no discernible content".
# Measured here: real photos reach at most 0.535 against a blank, while the
# genuinely empty one in this project scores 0.753.
BLANK_SIMILARITY = float(os.getenv("BLANK_SIMILARITY", "0.65"))
# Calibration of centred similarity → the 0-100 confidence the app displays.
# Midpoint is the similarity that reads as 50/100 (the FR 3.4 boundary);
# steepness sets how fast confidence climbs either side of it.
#
# A match must satisfy TWO independent conditions: it has to look like the
# query on its own merit, AND it has to clearly beat the other candidates.
# Measured across every real query available:
#
#     correct matches ............ similarity 25.0-37.8, lead +8.3 to +13.7
#     runner-ups (wrong) ......... similarity 16.5-24.1, lead negative
#     top item, target absent .... similarity  0.0-16.5, lead +16.5 to +18.7
#
# Neither signal decides it alone. A wrong runner-up can reach 24.1 — above a
# genuine close-up's 25.0 by a hair — so similarity alone can't separate them.
# And when the sought item simply isn't there, whatever ranks top leads the
# field by MORE than any real match does, so the lead alone is worse still.
# Requiring both (the two curves multiply) separates all three groups cleanly.
CONFIDENCE_MIDPOINT = float(os.getenv("CONFIDENCE_MIDPOINT", "20"))
CONFIDENCE_STEEPNESS = float(os.getenv("CONFIDENCE_STEEPNESS", "0.6"))
LEAD_MIDPOINT = float(os.getenv("LEAD_MIDPOINT", "-2"))
LEAD_STEEPNESS = float(os.getenv("LEAD_STEEPNESS", "0.34"))
# When nothing clears MATCH_THRESHOLD, still return this many closest items, so
# a search never comes back empty on an item that IS in the system.
FALLBACK_RESULTS = int(os.getenv("FALLBACK_RESULTS", "3"))


def _power_normalize(x: np.ndarray) -> np.ndarray:
    """Square-root ("power") normalization to unit length — standard for
    pooled CNN descriptors. It stops a few hugely-activated dimensions from
    dominating, and the unit length means centring compares directions rather
    than magnitudes: without it, any two faint photos both collapse toward
    -mu and score as a near-perfect match for each other.
    """
    p = np.sqrt(np.clip(x, 0, None))
    return p / np.clip(np.linalg.norm(p, axis=-1, keepdims=True), 1e-8, None)


def corpus_mean(vectors: list) -> Optional[np.ndarray]:
    """Average embedding across the candidate items — see reason 1 above."""
    if len(vectors) < MIN_CORPUS_FOR_CENTERING:
        return None
    return _power_normalize(np.stack(vectors)).mean(axis=0)


def centred_similarity(
    a: np.ndarray, b: np.ndarray, mu: Optional[np.ndarray]
) -> float:
    """Cosine similarity with the corpus average removed from both sides.

    Gated by the plain cosine: two images that aren't alike to begin with
    can't be rescued by centring. Falls back to plain cosine when there aren't
    enough items to centre on.
    """
    raw = cosine_similarity(a, b)
    if mu is None:
        return raw
    if raw < RAW_SIMILARITY_FLOOR:
        return 0.0
    return cosine_similarity(_power_normalize(a) - mu,
                             _power_normalize(b) - mu)


def _solid_image_bytes(level: int) -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (224, 224), (level, level, level)).save(buf, format="JPEG")
    return buf.getvalue()


_BLANK_REFS = [extract_vector(_solid_image_bytes(v)) for v in (0, 128, 255)]


def is_contentless(vector: np.ndarray) -> bool:
    """True when an embedding is that of a blank photo — see reason 2 above."""
    return any(cosine_similarity(vector, ref) >= BLANK_SIMILARITY
               for ref in _BLANK_REFS)


def _sigmoid(x: float) -> float:
    return float(1.0 / (1.0 + np.exp(-x)))


def confidence_score(similarity: float,
                     best_other: Optional[float] = None) -> float:
    """Centred similarity → calibrated 0-100 match score — see reason 3.

    [best_other] is the highest similarity among the *other* candidates for
    the same query. The two curves multiply, so an item only scores highly
    when it both resembles the query and out-distances everything else — see
    the measurements above CONFIDENCE_MIDPOINT for why either alone misleads.
    Without [best_other] (a single candidate), only the resemblance counts.
    """
    s = similarity * 100.0
    confidence = _sigmoid(CONFIDENCE_STEEPNESS * (s - CONFIDENCE_MIDPOINT))
    if best_other is not None:
        lead = s - best_other * 100.0
        confidence *= _sigmoid(LEAD_STEEPNESS * (lead - LEAD_MIDPOINT))
    return float(100.0 * confidence)


def building_of(location: Optional[str]) -> str:
    """The building/area from a composed 'Building — Spot' location string.

    The app's location picker joins the two levels with an em dash, e.g.
    'Block A — Lecture Hall', so the building is everything before the dash.
    Lower-cased for case-insensitive comparison; '' when unknown.
    """
    if not location:
        return ""
    # Split on em dash (the picker's separator) or a plain hyphen, just in case.
    for sep in ("—", " - ", "-"):
        if sep in location:
            return location.split(sep)[0].strip().lower()
    return location.strip().lower()


_STOPWORDS = {"the", "a", "an", "and", "of", "with", "for", "on", "in", "my",
              "is", "it", "item", "found", "lost", "at", "to"}


def text_similarity(a: Optional[str], b: Optional[str]) -> float:
    """Word-overlap (Jaccard) of two texts, 0..1 — a lightweight text signal to
    blend with the image score. Ignores common stopwords."""
    def toks(s):
        return {w for w in re.findall(r"[a-z0-9]+", (s or "").lower())
                if w not in _STOPWORDS and len(w) > 1}
    ta, tb = toks(a), toks(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def blended_score(image_confidence: float, text_a: str, text_b: str) -> float:
    """Combine an image match score with text overlap into a 0..100 score.

    [image_confidence] is already on the calibrated 0-100 scale from
    confidence_score(), the same scale the search results use — so the notify
    thresholds mean the same thing as MATCH_THRESHOLD. Passing a raw cosine
    here instead is what silently broke match alerts: centred similarity tops
    out near 0.35, so the blended score never exceeded ~28 against a
    threshold of 75, and no alert could ever fire.
    """
    txt = text_similarity(text_a, text_b)
    image_confidence = min(max(image_confidence, 0.0), 100.0)
    return IMAGE_WEIGHT * image_confidence + TEXT_WEIGHT * txt * 100.0


def _item_text(row: dict) -> str:
    """The searchable text for an item: category + description."""
    return f"{row.get('category', '')} {row.get('description', '')}"


def _parse_embedding(raw) -> Optional[np.ndarray]:
    """pgvector returns a string like '[0.1,0.2,...]'; arrays come back as lists.

    A cached vector of the wrong length was written by a different version of
    the extractor. It's treated as a cache miss and recomputed from the item's
    photo — comparing mismatched lengths would otherwise crash the search.
    """
    if raw is None:
        return None
    if isinstance(raw, list):
        vec = np.array(raw, dtype=np.float32)
    elif isinstance(raw, str):
        try:
            vec = np.array(json.loads(raw), dtype=np.float32)
        except Exception:
            return None
    else:
        return None
    return vec if vec.size == VECTOR_DIM else None


def _persist_embedding(table: str, item_id: str, vector: np.ndarray) -> None:
    """Best-effort cache of the vector back into Supabase so future searches
    are fast. Silently ignored if the `embedding` column does not exist or is
    sized for a different version of the extractor."""
    if supabase is None:
        return
    try:
        vec_str = "[" + ",".join(f"{x:.6f}" for x in vector.tolist()) + "]"
        supabase.table(table).update({"embedding": vec_str}).eq(
            "id", item_id
        ).execute()
    except Exception as e:
        print(f"(note) could not persist embedding for {item_id}: {e}")


def embedding_for_row(table: str, row: dict) -> Optional[np.ndarray]:
    """Return a row's vector — from the cached `embedding` column if present,
    otherwise download its image, compute it, and cache it (lazy indexing)."""
    vec = _parse_embedding(row.get("embedding"))
    if vec is not None:
        return vec
    image_url = row.get("image_url")
    if not image_url:
        return None
    try:
        img_bytes = requests.get(image_url, timeout=15).content
        vec = extract_vector(img_bytes)
        _persist_embedding(table, row["id"], vec)
        return vec
    except Exception as e:
        print(f"(skip) could not process {row.get('id')} in {table}: {e}")
        return None


# ── Routes ───────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {
        "status": "ok",
        "model": "MobileNetV2 R-MAC + colour",
        "vector_dim": VECTOR_DIM,
        "color_weight": COLOR_WEIGHT,
    }


@app.post("/extract")
async def extract(file: UploadFile = File(...)):
    """Returns the raw feature vector for an uploaded image."""
    try:
        vec = extract_vector(await file.read())
        return {"vector": vec.tolist(), "dim": len(vec)}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image: {e}")


@app.post("/search")
async def search(
    file: UploadFile = File(...),
    category: str = Form(default=""),
    top_k: int = Form(default=8),
):
    """
    FR 3.1–3.5: compare a query image against found items, returning a ranked
    list of matches at or above the configured match-score threshold.

    Relevance controls:
      • category — when set to anything other than "Any", a filter: the person
        is telling us what the item is, so another kind of item is simply the
        wrong answer
      • top_k    — cap on how many of the best matches are returned
    """
    if supabase is None:
        raise HTTPException(status_code=500, detail="Supabase is not configured.")

    # 1. Extract the query vector
    try:
        query_bytes = await file.read()
        if SAVE_QUERIES_DIR:
            # Diagnostic aid: keep the photo actually searched with, so a
            # disappointing result can be reproduced and measured offline
            # instead of guessed at. Off unless SAVE_QUERIES_DIR is set.
            try:
                os.makedirs(SAVE_QUERIES_DIR, exist_ok=True)
                path = os.path.join(
                    SAVE_QUERIES_DIR, f"query_{int(time.time())}.jpg")
                with open(path, "wb") as fh:
                    fh.write(query_bytes)
                # Plain ASCII arrow: the Windows console uses cp1252, which
                # cannot encode "→" and would fail the whole save step.
                print(f"[search] saved query photo -> {path}")
            except Exception as e:
                print(f"(note) could not save query photo: {e}")
        query_vec = extract_vector(query_bytes)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image: {e}")

    # A blank photo has nothing to match on; its nearest neighbours are noise.
    if is_contentless(query_vec):
        print("[search] query photo has no discernible content — no matches")
        return {"matches": [], "count": 0}

    want_category = category.strip().lower() if category else ""
    if want_category in ("any", "all", "any category"):
        want_category = ""

    # 2. Fetch all found items
    try:
        rows = supabase.table(FOUND_TABLE).select("*").execute().data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")

    # 3. Embed each item (lazy-indexing anything without a cached vector),
    #    dropping the ones whose photo shows nothing.
    usable = []
    skipped_blank = 0
    for row in rows:
        vec = embedding_for_row(FOUND_TABLE, row)
        if vec is None:
            continue
        if is_contentless(vec):
            skipped_blank += 1
            continue
        usable.append((row, vec))

    # 4. The corpus average, taken over EVERY usable photo — deliberately
    #    before the category filter, because it describes what photos in
    #    general look like. Averaging a filtered handful would leave too few to
    #    estimate from, silently dropping back to uncentred scores and their
    #    inflated floor, which makes a shoe look like an 85% match for a
    #    bottle. The query is excluded too: folding it in would drag the
    #    average toward the very thing being searched for.
    mu = corpus_mean([v for _, v in usable])

    candidates = [
        (row, vec) for row, vec in usable
        if not want_category
        or (row.get("category") or "").strip().lower() == want_category
    ]
    skipped_category = len(usable) - len(candidates)

    # 5. Similarity for every candidate first, so each can be scored against
    #    the field rather than on an absolute cutoff — see confidence_score.
    sims = [centred_similarity(query_vec, vec, mu) for _, vec in candidates]

    matches = []
    scored = []  # every item's score, for the console log below — even rejects
    for idx, ((row, _vec), sim) in enumerate(zip(candidates, sims)):
        others = [s for j, s in enumerate(sims) if j != idx]
        score = confidence_score(sim, max(others) if others else None)
        scored.append((round(score, 1), row.get("category"), row.get("id")))
        if score >= MATCH_THRESHOLD:
            matches.append(
                {
                    "id": row.get("id"),
                    "image_url": row.get("image_url", ""),
                    "category": row.get("category", "Unknown"),
                    "location_found": row.get("location_found", ""),
                    "description": row.get("description", ""),
                    "tags": row.get("tags", []),
                    "confidence_score": round(score, 1),
                    "created_at": row.get("created_at", ""),
                }
            )

    # 6. Rank highest-first and keep only the best top_k
    matches.sort(key=lambda m: m["confidence_score"], reverse=True)
    if top_k > 0:
        matches = matches[:top_k]

    # Nothing cleared the bar: return the closest few rather than an empty
    # screen. Each carries its own low score, so a weak match looks weak — but
    # a real item sitting just under the threshold still reaches the person
    # looking for it, which an empty list never does.
    if not matches and scored:
        by_id = {row.get("id"): row for row, _ in candidates}
        for score, _, item_id in sorted(
            ((s, c, i) for s, c, i in scored if s > 0), reverse=True
        )[:FALLBACK_RESULTS]:
            row = by_id.get(item_id)
            if row is None:
                continue
            matches.append(
                {
                    "id": row.get("id"),
                    "image_url": row.get("image_url", ""),
                    "category": row.get("category", "Unknown"),
                    "location_found": row.get("location_found", ""),
                    "description": row.get("description", ""),
                    "tags": row.get("tags", []),
                    "confidence_score": score,
                    "created_at": row.get("created_at", ""),
                }
            )

    # Log every candidate's score (not just the ones that passed) so a "no
    # match" can be diagnosed: borderline-but-filtered vs. genuinely dissimilar.
    scored.sort(key=lambda s: s[0], reverse=True)
    notes = ""
    if skipped_category:
        notes += f", {skipped_category} skipped (other category)"
    if skipped_blank:
        notes += f", {skipped_blank} skipped (blank photo)"
    print(f"[search] {len(scored)} found item(s) scored, "
          f"threshold={MATCH_THRESHOLD}{notes}:")
    for score, cat, item_id in scored[:10]:
        flag = "PASS" if score >= MATCH_THRESHOLD else "below"
        print(f"    {score:5.1f}%  [{flag}]  {cat}  {item_id}")

    return {"matches": matches, "count": len(matches)}


def notification_exists(user_id, item_id) -> bool:
    """True if this user was already alerted about this item — used to avoid
    pinging the same person repeatedly about the same match."""
    if supabase is None or not user_id or not item_id:
        return False
    try:
        rows = (
            supabase.table("notifications")
            .select("id")
            .eq("user_id", user_id)
            .eq("item_id", item_id)
            .limit(1)
            .execute()
            .data
        )
        return bool(rows)
    except Exception:
        return False


@app.post("/ingest-found")
async def ingest_found(item_id: str = Form(...)):
    """
    FR 4.3 / 4.4 — Background matching agent.
    Called when a new FOUND item is reported. Compares it against every active
    (unresolved) LOST report and notifies the lost item's owner when either:
      • the photos match above NOTIFY_THRESHOLD (boosted if same building), or
      • it's the SAME building + SAME category as their lost report — so a loser
        is alerted even when their photo doesn't visually match (or they had none).
    """
    if supabase is None:
        raise HTTPException(status_code=500, detail="Supabase is not configured.")

    # 1. Load the newly reported found item
    try:
        found_rows = (
            supabase.table(FOUND_TABLE).select("*").eq("id", item_id).limit(1)
            .execute().data
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")
    if not found_rows:
        raise HTTPException(status_code=404, detail="Found item not found.")

    found = found_rows[0]
    print(f"[ingest-found] new found item {item_id[:8]} "
          f"({found.get('category')}) — matching against lost reports")
    found_vec = embedding_for_row(FOUND_TABLE, found)     # may be None
    if found_vec is not None and is_contentless(found_vec):
        found_vec = None  # blank photo: fall back to location/category signals
    found_building = building_of(found.get("location_found"))
    found_category = (found.get("category") or "").strip().lower()

    # 2. Compare against all active lost reports
    try:
        lost_rows = supabase.table(LOST_TABLE).select("*").execute().data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")

    # Never match an item against its own reporter's lost reports: telling the
    # finder "someone found your item" about the thing they just handed in is
    # nonsense, and it happens easily since a user can be both a finder and a
    # loser (and often files similar-looking reports while testing).
    active_lost = [
        (lr, embedding_for_row(LOST_TABLE, lr))
        for lr in lost_rows
        if not lr.get("is_resolved") and lr.get("user_id") != found.get("user_id")
    ]

    # Centre on the FOUND items, not on the handful of lost reports. The
    # corpus average only has to describe what photos in general look like,
    # and there are usually far more found items than active lost reports —
    # too few and centring switches off, which silently feeds raw similarities
    # (~0.28 even for unrelated things) into a calibration built for centred
    # ones, making everything look like a match.
    try:
        corpus_rows = supabase.table(FOUND_TABLE).select("*").execute().data or []
    except Exception:
        corpus_rows = []
    corpus = [v for v in (embedding_for_row(FOUND_TABLE, r) for r in corpus_rows)
              if v is not None and not is_contentless(v)]
    mu = corpus_mean(corpus)

    # Similarity to every lost report first, so each can be scored against the
    # field rather than on an absolute cutoff — same reasoning as /search.
    lost_sims = [
        centred_similarity(found_vec, lvec, mu)
        if (found_vec is not None and lvec is not None
            and not is_contentless(lvec)) else None
        for _lr, lvec in active_lost
    ]

    notified = 0
    for idx, (lr, lvec) in enumerate(active_lost):
        same_building = bool(found_building) and \
            building_of(lr.get("location_found")) == found_building
        same_category = bool(found_category) and \
            (lr.get("category") or "").strip().lower() == found_category

        # Visual match, boosted (never excluded) by same building / same
        # category — a mismatch on either must not hide a real photo match,
        # since the finder and loser often log the building or category
        # slightly differently for the same physical item.
        if found_vec is not None:
            sim = lost_sims[idx]
            if sim is None:
                continue
            others = [s for j, s in enumerate(lost_sims)
                      if j != idx and s is not None]
            score = blended_score(
                confidence_score(sim, max(others) if others else None),
                _item_text(found), _item_text(lr))
            if same_building:
                score = min(100.0, score + LOCATION_BOOST)
            if same_category:
                score = min(100.0, score + CATEGORY_BOOST)
        elif same_building and same_category:
            # No usable photo at all: location + category is the only signal.
            score = SAME_BUILDING_MATCH_SCORE
        else:
            continue

        # Alert on a strong photo score, OR on the strong building+category
        # signal alone (even if that didn't push the score past NOTIFY_THRESHOLD).
        alert = score >= NOTIFY_THRESHOLD or (same_building and same_category)
        if not alert:
            continue

        # De-dupe: don't alert the same person about the same item twice.
        if notification_exists(lr.get("user_id"), found.get("id")):
            continue

        # 3. Notify the owner of the lost report (FR 4.4)
        same_building_note = (
            " It was found in the same building you reported."
            if same_building else ""
        )
        try:
            supabase.table("notifications").insert(
                {
                    "user_id": lr.get("user_id"),
                    "title": f"Possible match found (score {round(score)}/100)",
                    "message": (
                        f"A {found.get('category', 'item')} matching your lost "
                        f"report was just reported found at "
                        f"{found.get('location_found', 'campus')}.{same_building_note}"
                    ),
                    "item_id": found.get("id"),
                    "is_read": False,
                }
            ).execute()
            notified += 1
        except Exception as e:
            print(f"(note) could not insert notification: {e}")

    print(f"[ingest-found] {len(active_lost)} active lost report(s) checked, "
          f"{notified} owner(s) notified (threshold {NOTIFY_THRESHOLD})")
    return {"notified": notified}


@app.post("/ingest-lost")
async def ingest_lost(item_id: str = Form(...)):
    """
    Reverse-direction matching. Called when a new LOST item is reported.
    Compares it against every already-reported FOUND item and, if a match is
    above LOST_NOTIFY_THRESHOLD (a more lenient bar than the forward alert),
    alerts the LOSER — so it works even when the finder posted first.
    """
    if supabase is None:
        raise HTTPException(status_code=500, detail="Supabase is not configured.")

    # 1. Load the newly reported lost item
    try:
        lost_rows = (
            supabase.table(LOST_TABLE).select("*").eq("id", item_id).limit(1)
            .execute().data
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")
    if not lost_rows:
        raise HTTPException(status_code=404, detail="Lost item not found.")

    lost = lost_rows[0]
    print(f"[ingest-lost] new lost report {item_id[:8]} "
          f"({lost.get('category')}) — matching against found items")
    lost_vec = embedding_for_row(LOST_TABLE, lost)       # may be None (no photo)
    if lost_vec is not None and is_contentless(lost_vec):
        lost_vec = None  # blank photo: fall back to location/category signals
    lost_building = building_of(lost.get("location_found"))
    lost_category = (lost.get("category") or "").strip().lower()

    # 2. Compare against all found items
    try:
        found_rows = supabase.table(FOUND_TABLE).select("*").execute().data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")

    # Embed the still-available found items up front so the comparison can be
    # centred on this corpus, exactly as /search does.
    embedded = [(fr, embedding_for_row(FOUND_TABLE, fr)) for fr in found_rows]

    # The corpus average comes from EVERY found photo, before any filtering —
    # it only has to describe what photos in general look like. Averaging the
    # filtered subset could leave too few to estimate from, and centring would
    # silently switch off, feeding raw similarities into a calibration built
    # for centred ones and making unrelated items look like matches.
    mu = corpus_mean([v for _, v in embedded
                      if v is not None and not is_contentless(v)])

    # Same self-match rule as /ingest-found in reverse: never offer someone an
    # item they reported found themselves as a match for their own lost report.
    available_found = [
        (fr, vec) for fr, vec in embedded
        if not fr.get("is_returned") and fr.get("user_id") != lost.get("user_id")
    ]

    # Similarity to every found item first, so each can be scored against the
    # field rather than on an absolute cutoff — same reasoning as /search.
    found_sims = [
        centred_similarity(lost_vec, fvec, mu)
        if (lost_vec is not None and fvec is not None
            and not is_contentless(fvec)) else None
        for _fr, fvec in available_found
    ]

    # Find the single best match so we don't spam the loser with duplicates.
    best_score = 0.0
    best_found = None
    best_same_building = False
    for idx, (fr, fvec) in enumerate(available_found):
        same_building = bool(lost_building) and \
            building_of(fr.get("location_found")) == lost_building

        same_category = bool(lost_category) and \
            (fr.get("category") or "").strip().lower() == lost_category

        if lost_vec is not None:
            # Image available: score by visual similarity, boosted (never
            # excluded) by same building / same category — a mismatch on
            # either must not hide a real photo match.
            sim = found_sims[idx]
            if sim is None:
                continue
            others = [s for j, s in enumerate(found_sims)
                      if j != idx and s is not None]
            score = blended_score(
                confidence_score(sim, max(others) if others else None),
                _item_text(lost), _item_text(fr))
            if same_building:
                score = min(100.0, score + LOCATION_BOOST)
            if same_category:
                score = min(100.0, score + CATEGORY_BOOST)
        elif same_building and same_category:
            # No photo on the lost report: fall back to same building + same
            # category as the only signal available.
            score = SAME_BUILDING_MATCH_SCORE
        else:
            continue

        if score > best_score:
            best_score = score
            best_found = fr
            best_same_building = same_building

    if best_found is None or best_score < LOST_NOTIFY_THRESHOLD:
        print(f"[ingest-lost] best match scored {best_score:.1f}, below the "
              f"{LOST_NOTIFY_THRESHOLD} threshold — owner not notified")
        return {"notified": 0, "best_score": round(best_score, 1)}

    # De-dupe: don't re-alert the loser about an item they were already told about.
    if notification_exists(lost.get("user_id"), best_found.get("id")):
        return {"notified": 0, "duplicate": True, "best_score": round(best_score, 1)}

    # 3. Alert the loser (owner of this lost report)
    same_building_note = (
        " It was found in the same building you reported."
        if best_same_building else ""
    )
    try:
        supabase.table("notifications").insert(
            {
                "user_id": lost.get("user_id"),
                "title": f"Possible match found (score {round(best_score)}/100)",
                "message": (
                    f"A {best_found.get('category', 'item')} matching your lost "
                    f"report may already be waiting — reported found at "
                    f"{best_found.get('location_found', 'campus')}.{same_building_note}"
                ),
                "item_id": best_found.get("id"),
                "is_read": False,
            }
        ).execute()
    except Exception as e:
        print(f"(note) could not insert notification: {e}")
        return {"notified": 0}

    print(f"[ingest-lost] owner notified about found item "
          f"{str(best_found.get('id'))[:8]} (score {best_score:.1f})")
    return {
        "notified": 1,
        "best_score": round(best_score, 1),
        "same_building": best_same_building,
    }
