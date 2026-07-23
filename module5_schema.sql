-- ============================================================
--  Module 5 — Secure Claim & Handover
--  Run this whole file in the Supabase SQL Editor.
-- ============================================================

-- 0. Remove any stale/old versions of these objects so the correct Module 5
--    structure is guaranteed. These tables hold no real app data.
drop function if exists public.submit_claim(uuid, text);
drop table if exists public.claim_messages cascade;
drop table if exists public.messages       cascade;  -- old unused chat table
drop table if exists public.claims         cascade;
drop table if exists public.item_secrets   cascade;

-- 1. Security question lives on the found item (the ANSWER is stored separately)
alter table public.found_items add column if not exists security_question text;

-- 1b. Notifications get a type so the app can route them (e.g. a 'claim_request'
--     alert opens the Requests tab; match alerts keep their default behaviour).
alter table public.notifications add column if not exists type text;

-- 2. Secret answers — locked down so ONLY the finder can read them.
--    Claimants can never select this table (Zero-Trust).
create table if not exists public.item_secrets (
  item_id uuid primary key references public.found_items(id) on delete cascade,
  answer  text not null
);
alter table public.item_secrets enable row level security;

drop policy if exists "secrets_owner_all" on public.item_secrets;
create policy "secrets_owner_all" on public.item_secrets
  for all
  using  (auth.uid() = (select user_id from public.found_items where id = item_id))
  with check (auth.uid() = (select user_id from public.found_items where id = item_id));

-- 3. Claims
create table if not exists public.claims (
  id            uuid primary key default gen_random_uuid(),
  found_item_id uuid not null references public.found_items(id) on delete cascade,
  claimant_id   uuid not null references auth.users(id) on delete cascade,
  finder_id     uuid not null references auth.users(id) on delete cascade,
  status        text not null default 'Quiz',  -- Quiz, Pending, Verified, Rejected, Returned
  quiz_attempts int default 0,
  is_locked     boolean default false,
  safe_zone     text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now(),
  unique (found_item_id, claimant_id)
);
alter table public.claims enable row level security;

drop policy if exists "claims_select" on public.claims;
create policy "claims_select" on public.claims for select
  using (auth.uid() = claimant_id or auth.uid() = finder_id);

drop policy if exists "claims_update" on public.claims;
create policy "claims_update" on public.claims for update
  using (auth.uid() = claimant_id or auth.uid() = finder_id);
-- NOTE: rows are inserted only via submit_claim() below, never directly.

-- 4. Masked chat messages (no phone numbers ever stored)
create table if not exists public.claim_messages (
  id         uuid primary key default gen_random_uuid(),
  claim_id   uuid not null references public.claims(id) on delete cascade,
  sender_id  uuid not null references auth.users(id) on delete cascade,
  body       text not null,
  created_at timestamptz default now()
);
alter table public.claim_messages enable row level security;

drop policy if exists "msg_select" on public.claim_messages;
create policy "msg_select" on public.claim_messages for select
  using (exists (
    select 1 from public.claims c
    where c.id = claim_id and (auth.uid() = c.claimant_id or auth.uid() = c.finder_id)
  ));

drop policy if exists "msg_insert" on public.claim_messages;
create policy "msg_insert" on public.claim_messages for insert
  with check (
    auth.uid() = sender_id and exists (
      select 1 from public.claims c
      where c.id = claim_id and c.status = 'Verified'
        and (auth.uid() = c.claimant_id or auth.uid() = c.finder_id)
    )
  );

-- live chat updates
alter publication supabase_realtime add table public.claim_messages;

-- 5. Zero-Trust verification function — checks the answer SERVER-SIDE so the
--    secret never leaves the database. Handles the 3-attempt lock (NFR 3.1).
create or replace function public.submit_claim(p_item_id uuid, p_answer text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_finder   uuid;
  v_category text;
  v_answer   text;
  v_id       uuid;
  v_attempts int;
  v_locked   boolean;
  v_status   text;
begin
  if v_uid is null then return 'NOT_AUTHENTICATED'; end if;

  select user_id, category into v_finder, v_category
    from found_items where id = p_item_id;
  if v_finder is null then return 'ITEM_NOT_FOUND'; end if;
  if v_finder = v_uid then return 'OWN_ITEM'; end if;

  select answer into v_answer from item_secrets where item_id = p_item_id;
  if v_answer is null then return 'NO_QUESTION'; end if;

  select id, quiz_attempts, is_locked, status
    into v_id, v_attempts, v_locked, v_status
    from claims where found_item_id = p_item_id and claimant_id = v_uid;

  if v_id is not null then
    if v_locked then return 'LOCKED'; end if;
    if v_status in ('Pending','Verified','Returned') then return 'ALREADY'; end if;
    if v_status = 'Rejected' then return 'REJECTED'; end if;
  end if;

  if lower(btrim(v_answer)) = lower(btrim(p_answer)) then
    if v_id is null then
      insert into claims(found_item_id, claimant_id, finder_id, status)
        values (p_item_id, v_uid, v_finder, 'Pending');
    else
      update claims set status = 'Pending', updated_at = now() where id = v_id;
    end if;
    -- Notify the finder so they don't have to keep checking the Requests tab.
    -- (Runs under security definer, so it may write a row for another user.)
    insert into notifications(user_id, title, message, item_id, is_read, type)
      values (
        v_finder,
        'New claim request',
        'Someone passed the ownership question for your '
          || coalesce(v_category, 'item')
          || ' and wants to claim it. Open Requests to review.',
        p_item_id,
        false,
        'claim_request'
      );
    return 'PASSED';
  else
    if v_id is null then
      insert into claims(found_item_id, claimant_id, finder_id, status, quiz_attempts)
        values (p_item_id, v_uid, v_finder, 'Quiz', 1);
      return 'WRONG';
    else
      v_attempts := coalesce(v_attempts, 0) + 1;
      update claims set quiz_attempts = v_attempts,
             is_locked = (v_attempts >= 3), updated_at = now()
        where id = v_id;
      if v_attempts >= 3 then return 'LOCKED'; end if;
      return 'WRONG';
    end if;
  end if;
end;
$$;

grant execute on function public.submit_claim(uuid, text) to authenticated;
