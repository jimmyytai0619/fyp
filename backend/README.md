# SmartMatch — AI Visual Matching Backend

Python FastAPI service that powers **Module 3** (AI Visual Search & Matching).
It uses **MobileNetV2** to extract a 1280-dimensional feature vector from an
image, then ranks found items by **cosine similarity**.

## One-time setup

```bash
cd backend

# 1. Create and activate a virtual environment
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS/Linux

# 2. Install dependencies (downloads TensorFlow — a few minutes)
pip install -r requirements.txt

# 3. Configure secrets
copy .env.example .env       # Windows  (cp on macOS/Linux)
#   → open .env and paste your SUPABASE_SERVICE_ROLE_KEY
#     (Supabase Dashboard → Settings → API → service_role → Reveal)
```

## (Optional but recommended) Add the vector cache column

Run this in the **Supabase SQL Editor** so computed vectors are stored and
searches stay fast. Without it, the server still works — it just recomputes
vectors on every search.

```sql
create extension if not exists vector;
alter table public.found_items add column if not exists embedding vector(1280);
```

Also make sure your **`found-items` storage bucket is public** so the backend
can download item images (Storage → found-items → Settings → Public).

## Run the server

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

Leave this terminal running while you use the app. Check it works by opening
<http://localhost:8000/health> — you should see `{"status":"ok",...}`.

## How the Flutter app reaches it

| Where the app runs | URL it should call |
|---|---|
| Android **emulator** | `http://10.0.2.2:8000` (already set as default) |
| Real phone (same Wi-Fi) | `http://<your-PC-LAN-IP>:8000` |

The base URL lives in `lib/services/api_service.dart` → `aiBackendBaseUrl`.

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Sanity check |
| POST | `/extract` | Returns the raw 1280-dim vector for an image |
| POST | `/search` | Ranked matches for a query image (FR 3.1–3.5) |
