"""
SmartMatch — AI Visual Matching Backend
========================================
FastAPI service implementing Module 3 of the SmartMatch FYP:

  • MobileNetV2 feature extraction  (FR 3.2 — 1280-dim vector)
  • Cosine Similarity scoring        (FR 3.3)
  • 50% confidence threshold         (FR 3.4)
  • Ranked results with % score      (FR 3.5)

Run:
    uvicorn main:app --host 0.0.0.0 --port 8000
"""

import os
import io
import json
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
MATCH_THRESHOLD = float(os.getenv("MATCH_THRESHOLD", "50"))  # FR 3.4 — 50%
FOUND_TABLE = "found_items"

if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
    print("⚠️  SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY not set — check your .env")

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
print("✅ Model ready (1280-dim feature extractor).")

app = FastAPI(title="SmartMatch AI Matching API", version="1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Core AI helpers ──────────────────────────────────────────────────────────
def extract_vector(image_bytes: bytes) -> np.ndarray:
    """Algorithm 1: normalize image to [-1,1] and run MobileNetV2 forward pass."""
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB").resize((224, 224))
    arr = np.array(img, dtype=np.float32)
    arr = preprocess_input(arr)          # scales pixels to [-1, 1]
    arr = np.expand_dims(arr, axis=0)     # (1, 224, 224, 3)
    vector = model.predict(arr, verbose=0)[0]  # (1280,)
    return vector.astype(np.float32)


def cosine_similarity(a: np.ndarray, b: np.ndarray) -> float:
    """Algorithm 2: cosine similarity (angle between two vectors)."""
    denom = (np.linalg.norm(a) * np.linalg.norm(b))
    if denom == 0:
        return 0.0
    return float(np.dot(a, b) / denom)


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


def _persist_embedding(item_id: str, vector: np.ndarray) -> None:
    """Best-effort cache of the vector back into Supabase so future searches
    are fast. Silently ignored if the `embedding` column does not exist."""
    if supabase is None:
        return
    try:
        vec_str = "[" + ",".join(f"{x:.6f}" for x in vector.tolist()) + "]"
        supabase.table(FOUND_TABLE).update({"embedding": vec_str}).eq(
            "id", item_id
        ).execute()
    except Exception as e:
        print(f"(note) could not persist embedding for {item_id}: {e}")


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
    list of matches at or above the confidence threshold.

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
        vec = _parse_embedding(row.get("embedding"))

        if vec is None:
            image_url = row.get("image_url")
            if not image_url:
                continue
            try:
                img_bytes = requests.get(image_url, timeout=15).content
                vec = extract_vector(img_bytes)
                _persist_embedding(row["id"], vec)
            except Exception as e:
                print(f"(skip) could not process {row.get('id')}: {e}")
                continue

        score = cosine_similarity(query_vec, vec) * 100.0  # → percentage
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
