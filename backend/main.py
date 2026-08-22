"""
SmartMatch — AI Visual Matching Backend
========================================
FastAPI service implementing Module 3 of the SmartMatch FYP:

  • MobileNetV2 feature extraction  (FR 3.2 — 1280-dim vector)
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
# include_top=False + pooling='avg' → 1280-dimensional feature vector
print("Loading MobileNetV2 model (first run downloads ~14MB weights)...")
model = MobileNetV2(
    weights="imagenet",
    include_top=False,
    pooling="avg",
    input_shape=(224, 224, 3),
)
print("Model ready (1280-dim feature extractor).")

app = FastAPI(title="SmartMatch AI Matching API", version="1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Core AI helpers ──────────────────────────────────────────────────────────
def _preprocess_image(image_bytes: bytes) -> Image.Image:
    """Center-square-crop then resize to 224x224.

    Cropping to a centred square (instead of squishing the whole photo) keeps
    the aspect ratio and focuses the network on the object in the middle,
    reducing the influence of background clutter — which makes the resulting
    feature vectors far more discriminative for matching.
    """
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    return img.resize((224, 224))


def extract_vector(image_bytes: bytes) -> np.ndarray:
    """Algorithm 1: normalize image to [-1,1] and run MobileNetV2 forward pass.

    Uses test-time augmentation (original + horizontal flip, averaged) so the
    embedding is robust to left/right orientation of the item.
    """
    img = _preprocess_image(image_bytes)
    arr = preprocess_input(np.array(img, dtype=np.float32))  # → [-1, 1]
    batch = np.stack([arr, np.fliplr(arr)])                  # (2, 224, 224, 3)
    vectors = model.predict(batch, verbose=0)                # (2, 1280)
    return vectors.mean(axis=0).astype(np.float32)


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Algorithm 2: cosine similarity (angle between two vectors)."""
    denom = (np.linalg.norm(a) * np.linalg.norm(b))
    if denom == 0:
        return 0.0
    return float(np.dot(a, b) / denom)


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


def blended_score(image_cos: float, text_a: str, text_b: str) -> float:
    """Combine image cosine (0..1) with text overlap into a 0..100 score."""
    txt = text_similarity(text_a, text_b)
    return (IMAGE_WEIGHT * image_cos + TEXT_WEIGHT * txt) * 100.0


def _item_text(row: dict) -> str:
    """The searchable text for an item: category + description + any OCR text
    read off it (brand/label/number)."""
    return (f"{row.get('category', '')} {row.get('description', '')} "
            f"{row.get('ocr_text', '') or ''}")


def _parse_embedding(raw) -> Optional[np.ndarray]:
    """pgvector returns a string like '[0.1,0.2,...]'; arrays come back as lists."""
    if raw is None:
        return None
    if isinstance(raw, list):
        return np.array(raw, dtype=np.float32)
    if isinstance(raw, str):
        try:
            return np.array(json.loads(raw), dtype=np.float32)
        except Exception:
            return None
    return None


def _persist_embedding(table: str, item_id: str, vector: np.ndarray) -> None:
    """Best-effort cache of the vector back into Supabase so future searches
    are fast. Silently ignored if the `embedding` column does not exist."""
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
    return {"status": "ok", "model": "MobileNetV2", "vector_dim": 1280}


@app.post("/extract")
async def extract(file: UploadFile = File(...)):
    """Returns the raw 1280-dim feature vector for an uploaded image."""
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
      • category — optional hard filter (only compare items of the same type)
      • top_k    — cap on how many of the best matches are returned
    """
    if supabase is None:
        raise HTTPException(status_code=500, detail="Supabase is not configured.")

    # 1. Extract the query vector
    try:
        query_vec = extract_vector(await file.read())
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid image: {e}")

    # 2. Fetch found items, optionally hard-filtered by category
    try:
        query = supabase.table(FOUND_TABLE).select("*")
        if category and category.lower() not in ("", "any", "all"):
            query = query.eq("category", category)
        rows = query.execute().data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")

    # 3. Score each item (lazy-indexing any item without a cached vector)
    matches = []
    for row in rows:
        vec = embedding_for_row(FOUND_TABLE, row)
        if vec is None:
            continue

        score = cosine_similarity(query_vec, vec) * 100.0  # 0–100 similarity scale
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

    # 4. Rank highest-first and keep only the best top_k
    matches.sort(key=lambda m: m["confidence_score"], reverse=True)
    if top_k > 0:
        matches = matches[:top_k]
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
    found_vec = embedding_for_row(FOUND_TABLE, found)     # may be None
    found_building = building_of(found.get("location_found"))
    found_category = (found.get("category") or "").strip().lower()

    # 2. Compare against all active lost reports
    try:
        lost_rows = supabase.table(LOST_TABLE).select("*").execute().data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")

    notified = 0
    for lr in lost_rows:
        if lr.get("is_resolved"):
            continue

        same_building = bool(found_building) and \
            building_of(lr.get("location_found")) == found_building
        same_category = bool(found_category) and \
            (lr.get("category") or "").strip().lower() == found_category

        alert = False
        score = 0.0

        # (a) Visual match, boosted when it's the same building.
        if found_vec is not None:
            lvec = embedding_for_row(LOST_TABLE, lr)
            if lvec is not None:
                score = blended_score(
                    cosine_similarity(found_vec, lvec),
                    _item_text(found), _item_text(lr))
                if same_building:
                    score = min(100.0, score + LOCATION_BOOST)
                if score >= NOTIFY_THRESHOLD:
                    alert = True

        # (b) Location signal: same building + same category always alerts, even
        #     if the photos don't match or the lost report has no photo.
        if not alert and same_building and same_category:
            alert = True
            score = max(score, SAME_BUILDING_MATCH_SCORE)

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
    lost_vec = embedding_for_row(LOST_TABLE, lost)       # may be None (no photo)
    lost_building = building_of(lost.get("location_found"))
    lost_category = (lost.get("category") or "").strip().lower()

    # 2. Compare against all found items
    try:
        found_rows = supabase.table(FOUND_TABLE).select("*").execute().data or []
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Database error: {e}")

    # Find the single best match so we don't spam the loser with duplicates.
    best_score = 0.0
    best_found = None
    best_same_building = False
    for fr in found_rows:
        if fr.get("is_returned"):
            continue  # already handed back — stop matching against it
        same_building = bool(lost_building) and \
            building_of(fr.get("location_found")) == lost_building

        if lost_vec is not None:
            # Image available: score by visual similarity, boosted if same building.
            fvec = embedding_for_row(FOUND_TABLE, fr)
            if fvec is None:
                continue
            score = blended_score(
                cosine_similarity(lost_vec, fvec),
                _item_text(lost), _item_text(fr))
            if same_building:
                score = min(100.0, score + LOCATION_BOOST)
        elif same_building and lost_category and \
                (fr.get("category") or "").strip().lower() == lost_category:
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

    return {
        "notified": 1,
        "best_score": round(best_score, 1),
        "same_building": best_same_building,
    }
