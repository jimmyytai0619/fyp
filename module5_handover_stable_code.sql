-- ─────────────────────────────────────────────────────────────────────────────
-- Handover code: stable per claim instead of regenerated on every call
-- ─────────────────────────────────────────────────────────────────────────────
-- The original start_handover() minted a fresh random code on EVERY call, and
-- the app calls it each time the finder opens the handover screen. So the code
-- (and its QR) changed constantly, and worse: if the finder reopened the screen
-- while the claimant was still typing, the code they were typing had already
-- been overwritten and verification failed with BAD_CODE.
--
-- Now the code is created once per claim and returned unchanged thereafter.
-- The finder can still rotate it deliberately by passing p_regenerate => true
-- (the "Generate a new code" button), which is the only thing that invalidates
-- the old one.
--
-- Scope note: the code is stable per CLAIM, not per ITEM. A claim is one item
-- plus one specific claimant, so if two people claim the same item they get
-- different codes — a per-item code would let either of them verify a handover
-- meant for the other.
--
-- Run this in the Supabase SQL Editor.

-- The one-argument version has to go, or calling start_handover by name with a
-- single parameter becomes ambiguous between the two overloads.
drop function if exists public.start_handover(uuid);

create or replace function public.start_handover(
  p_claim_id   uuid,
  p_regenerate boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_finder uuid;
  v_status text;
  v_code   text;
begin
  if v_uid is null then return 'NOT_AUTHENTICATED'; end if;
  select finder_id, status into v_finder, v_status from claims where id = p_claim_id;
  if v_finder is null then return 'NOT_FOUND'; end if;
  if v_finder <> v_uid then return 'NOT_FINDER'; end if;
  if v_status <> 'Verified' then return 'NOT_VERIFIED'; end if;

  if not p_regenerate then
    -- Reuse the existing code so the QR the claimant is looking at stays valid.
    select code into v_code from claim_handovers where claim_id = p_claim_id;
    if v_code is not null then return v_code; end if;
  end if;

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into claim_handovers(claim_id, code)
    values (p_claim_id, v_code)
    on conflict (claim_id) do update set code = excluded.code, created_at = now();
  return v_code;
end;
$$;

grant execute on function public.start_handover(uuid, boolean) to authenticated;
