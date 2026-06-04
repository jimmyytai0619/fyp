-- ============================================================
--  SmartMatch — Full Database Schema
--  Run this entire file in Supabase SQL Editor
-- ============================================================


-- ── 0. Extensions ────────────────────────────────────────────
-- enable pgvector for AI feature vector storage
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;


-- ── 1. PROFILES ──────────────────────────────────────────────
-- Extends Supabase auth.users with campus-specific fields
CREATE TABLE public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   TEXT NOT NULL,
  student_id  TEXT UNIQUE NOT NULL,
  phone       TEXT,
  avatar_url  TEXT,
  items_found     INT DEFAULT 0,
  items_returned  INT DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-create a profile row whenever a new user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, student_id, phone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'student_id', NEW.id::TEXT),
    COALESCE(NEW.raw_user_meta_data->>'phone', '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── 2. ITEM_REPORTS ──────────────────────────────────────────
-- Central record for every lost or found item on campus
CREATE TYPE item_status AS ENUM ('Lost', 'Found', 'Claimed', 'Returned');
CREATE TYPE item_category AS ENUM (
  'Electronics', 'Bags', 'Wallets', 'Keys',
  'ID_Cards', 'Clothing', 'Stationery', 'Others'
);

CREATE TABLE public.item_reports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  description     TEXT,
  category        item_category NOT NULL DEFAULT 'Others',
  status          item_status NOT NULL DEFAULT 'Found',
  location_found  TEXT,
  image_url       TEXT,
  security_question   TEXT,     -- set by finder for ownership quiz
  security_answer     TEXT,     -- hashed answer (store lowercase trimmed)
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-update updated_at on every change
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER item_reports_updated_at
  BEFORE UPDATE ON public.item_reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ── 3. ITEM_VECTORS ──────────────────────────────────────────
-- Stores the MobileNetV2 1280-dim feature vector for each item
-- Kept in a separate table to keep similarity queries fast
CREATE TABLE public.item_vectors (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_report_id  UUID UNIQUE NOT NULL REFERENCES public.item_reports(id) ON DELETE CASCADE,
  embedding       VECTOR(1280) NOT NULL,   -- MobileNetV2 global avg pool output
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- IVFFlat index for fast approximate nearest-neighbour search
-- (create AFTER you have inserted at least a few hundred rows)
-- CREATE INDEX ON public.item_vectors
--   USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);


-- ── 4. LOST_REPORTS (Background Agent) ───────────────────────
-- Saved active search queries — the background agent watches these
CREATE TABLE public.lost_reports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  query_text      TEXT,                    -- text keywords used
  query_vector    VECTOR(1280),            -- image vector used (nullable)
  category        item_category,
  is_resolved     BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);


-- ── 5. CLAIMS ────────────────────────────────────────────────
-- Tracks who is claiming which found item (Secure Handover Module)
CREATE TYPE claim_status AS ENUM ('Pending', 'Verified', 'Rejected', 'Returned');

CREATE TABLE public.claims (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_report_id  UUID NOT NULL REFERENCES public.item_reports(id) ON DELETE CASCADE,
  claimant_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status          claim_status NOT NULL DEFAULT 'Pending',
  quiz_attempts   INT DEFAULT 0,           -- locked after 3 failed attempts
  is_locked       BOOLEAN DEFAULT FALSE,
  safe_zone       TEXT,                    -- chosen campus handover location
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (item_report_id, claimant_id)
);

CREATE TRIGGER claims_updated_at
  BEFORE UPDATE ON public.claims
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- ── 6. MESSAGES (Masked Chat) ────────────────────────────────
-- In-app anonymous chat between finder and claimant
-- Phone numbers are never stored here — only in profiles
CREATE TABLE public.messages (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id    UUID NOT NULL REFERENCES public.claims(id) ON DELETE CASCADE,
  sender_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body        TEXT NOT NULL,
  is_read     BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);


-- ── 7. NOTIFICATION_LOG ──────────────────────────────────────
-- Tracks push alerts sent by the background agent
-- Prevents duplicate spam notifications
CREATE TABLE public.notification_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  lost_report_id  UUID REFERENCES public.lost_reports(id) ON DELETE SET NULL,
  item_report_id  UUID REFERENCES public.item_reports(id) ON DELETE SET NULL,
  match_score     FLOAT,                   -- cosine similarity % that triggered this
  is_read         BOOLEAN DEFAULT FALSE,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);


-- ── 8. SAFE_ZONES ────────────────────────────────────────────
-- Predefined CCTV-monitored campus handover locations
CREATE TABLE public.safe_zones (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  building    TEXT,
  latitude    FLOAT,
  longitude   FLOAT,
  is_active   BOOLEAN DEFAULT TRUE
);

-- Seed with TAR UMT safe zones
INSERT INTO public.safe_zones (name, building, latitude, longitude) VALUES
  ('Security Office',       'Main Guard Post',     3.2178, 101.7246),
  ('Library Help Desk',     'TAR UMT Library',     3.2181, 101.7251),
  ('Student Affairs Office','Block A, Level 1',    3.2175, 101.7248),
  ('Faculty Admin Counter', 'FICT Block, Level G', 3.2170, 101.7244);


-- ============================================================
--  ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE public.profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_reports      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_vectors      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lost_reports      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.claims            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_log  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safe_zones        ENABLE ROW LEVEL SECURITY;

-- profiles: users can read all, but only edit their own
CREATE POLICY "profiles_select_all"  ON public.profiles FOR SELECT USING (true);
CREATE POLICY "profiles_update_own"  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- item_reports: anyone authenticated can read; only owner can insert/update/delete
CREATE POLICY "items_select_all"     ON public.item_reports FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "items_insert_own"     ON public.item_reports FOR INSERT WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "items_update_own"     ON public.item_reports FOR UPDATE USING (auth.uid() = owner_id);
CREATE POLICY "items_delete_own"     ON public.item_reports FOR DELETE USING (auth.uid() = owner_id);

-- item_vectors: readable by all authenticated; inserted by backend service only
CREATE POLICY "vectors_select_all"   ON public.item_vectors FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "vectors_insert_own"   ON public.item_vectors FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- lost_reports: only the owner can see and manage their own searches
CREATE POLICY "lost_select_own"      ON public.lost_reports FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "lost_insert_own"      ON public.lost_reports FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "lost_update_own"      ON public.lost_reports FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "lost_delete_own"      ON public.lost_reports FOR DELETE USING (auth.uid() = user_id);

-- claims: claimant and item owner can both see the claim
CREATE POLICY "claims_select"        ON public.claims FOR SELECT
  USING (
    auth.uid() = claimant_id OR
    auth.uid() = (SELECT owner_id FROM public.item_reports WHERE id = item_report_id)
  );
CREATE POLICY "claims_insert_own"    ON public.claims FOR INSERT WITH CHECK (auth.uid() = claimant_id);
CREATE POLICY "claims_update"        ON public.claims FOR UPDATE
  USING (
    auth.uid() = claimant_id OR
    auth.uid() = (SELECT owner_id FROM public.item_reports WHERE id = item_report_id)
  );

-- messages: only participants of the related claim can read/write
CREATE POLICY "messages_select"      ON public.messages FOR SELECT
  USING (
    auth.uid() IN (
      SELECT claimant_id FROM public.claims WHERE id = claim_id
      UNION
      SELECT ir.owner_id FROM public.item_reports ir
        JOIN public.claims c ON c.item_report_id = ir.id WHERE c.id = claim_id
    )
  );
CREATE POLICY "messages_insert"      ON public.messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id);

-- notifications: users only see their own
CREATE POLICY "notif_select_own"     ON public.notification_log FOR SELECT USING (auth.uid() = user_id);

-- safe_zones: public read-only
CREATE POLICY "zones_select_all"     ON public.safe_zones FOR SELECT USING (true);
