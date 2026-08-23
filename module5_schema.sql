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

-- 1b. Notification columns the app/backend expect. `type` lets the app route an
--     alert (e.g. 'claim_request' → Requests tab); `item_id` is the found item
--     an alert points to (also used by the backend's AI-match notifications).
alter table public.notifications add column if not exists type text;
alter table public.notifications add column if not exists item_id uuid;
-- Handover proof photo, uploaded by the finder when marking an item returned.
alter table public.claims add column if not exists return_evidence_url text;
-- Lets a loser close a lost report so it stops generating match alerts.
alter table public.lost_items add column if not exists is_resolved boolean default false;

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
    -- Best-effort: a notification failure must NEVER fail the claim itself, so
    -- swallow any error here (e.g. a schema mismatch on the notifications table).
    begin
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
    exception when others then
      null; -- ignore: the claim already succeeded
    end;
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

-- 6. Finder approves / rejects a claim, and the claimant is notified. Security
--    definer so the status update AND the cross-user notification both bypass
--    RLS safely, while verifying that only the item's finder may decide.
create or replace function public.decide_claim(p_claim_id uuid, p_decision text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid       uuid := auth.uid();
  v_finder    uuid;
  v_claimant  uuid;
  v_item      uuid;
  v_category  text;
begin
  if v_uid is null then return 'NOT_AUTHENTICATED'; end if;
  if p_decision not in ('Verified','Rejected') then return 'BAD_DECISION'; end if;

  select c.finder_id, c.claimant_id, c.found_item_id, fi.category
    into v_finder, v_claimant, v_item, v_category
    from claims c
    join found_items fi on fi.id = c.found_item_id
    where c.id = p_claim_id;
  if not found then return 'NOT_FOUND'; end if;
  if v_finder <> v_uid then return 'NOT_FINDER'; end if;

  update claims set status = p_decision, updated_at = now() where id = p_claim_id;

  -- Notify the claimant (best-effort: never fail the decision over a message).
  begin
    insert into notifications(user_id, title, message, item_id, is_read, type)
      values (
        v_claimant,
        case when p_decision = 'Verified'
             then 'Claim approved'
             else 'Claim not approved' end,
        case when p_decision = 'Verified'
             then 'The finder approved your claim for the '
                  || coalesce(v_category, 'item')
                  || '. Open Messages to arrange the handover.'
             else 'The finder did not approve your claim for the '
                  || coalesce(v_category, 'item') || '.' end,
        v_item,
        false,
        'claim_decision'
      );
  exception when others then
    null; -- ignore: the status change already succeeded
  end;

  return 'OK';
end;
$$;

grant execute on function public.decide_claim(uuid, text) to authenticated;

-- 7. Either party marks the handover complete → the OTHER party is notified,
--    and the item counts toward the finder's "Items Returned" stat. Security
--    definer so the status update and cross-user notification bypass RLS, while
--    verifying the caller is actually part of this claim.
drop function if exists public.mark_returned(uuid);
create or replace function public.mark_returned(p_claim_id uuid,
                                                p_evidence_url text default null)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_finder   uuid;
  v_claimant uuid;
  v_item     uuid;
  v_category text;
  v_target   uuid;
  v_title    text;
  v_msg      text;
begin
  if v_uid is null then return 'NOT_AUTHENTICATED'; end if;

  select c.finder_id, c.claimant_id, c.found_item_id, fi.category
    into v_finder, v_claimant, v_item, v_category
    from claims c
    join found_items fi on fi.id = c.found_item_id
    where c.id = p_claim_id;
  if not found then return 'NOT_FOUND'; end if;
  if v_uid <> v_finder and v_uid <> v_claimant then return 'NOT_PARTY'; end if;

  -- Finder records the handover (with proof) → awaits the claimant's confirm.
  update claims set status = 'ReturnPending', updated_at = now(),
         return_evidence_url = coalesce(p_evidence_url, return_evidence_url)
    where id = p_claim_id;

  begin
    insert into notifications(user_id, title, message, item_id, is_read, type)
      values (
        v_claimant,
        'Confirm you received it',
        'The finder marked your ' || coalesce(v_category, 'item')
          || ' as handed over. Please confirm you received it.',
        v_item,
        false,
        'return_pending'
      );
  exception when others then null;
  end;

  return 'OK';
end;
$$;

grant execute on function public.mark_returned(uuid, text) to authenticated;

-- 10. Two-party return confirmation — claimant confirms/denies receipt.
create or replace function public.confirm_return(p_claim_id uuid, p_received boolean)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_finder   uuid;
  v_claimant uuid;
  v_item     uuid;
  v_category text;
begin
  if v_uid is null then return 'NOT_AUTHENTICATED'; end if;
  select c.finder_id, c.claimant_id, c.found_item_id, fi.category
    into v_finder, v_claimant, v_item, v_category
    from claims c join found_items fi on fi.id = c.found_item_id
    where c.id = p_claim_id;
  if not found then return 'NOT_FOUND'; end if;
  if v_uid <> v_claimant then return 'NOT_CLAIMANT'; end if;

  if p_received then
    update claims set status = 'Returned', updated_at = now() where id = p_claim_id;

    begin
      update found_items set is_returned = true where id = v_item;
    exception when others then null;
    end;

    begin
      update lost_items set is_resolved = true
        where user_id = v_claimant and category = v_category
          and coalesce(is_resolved, false) = false;
    exception when others then null;
    end;

    begin
      insert into notifications(user_id, title, message, item_id, is_read, type)
        values (v_finder, 'Return confirmed',
          'The owner confirmed they received the ' || coalesce(v_category, 'item')
            || '. Thanks for returning it!', v_item, false, 'return_confirmed');
    exception when others then null;
    end;

    return 'OK';
  else
    begin
      insert into notifications(user_id, title, message, item_id, is_read, type)
        values (v_finder, 'Return not confirmed',
          'The owner said they have not received the ' || coalesce(v_category, 'item')
            || ' yet. Please follow up.', v_item, false, 'return_disputed');
    exception when others then null;
    end;

    return 'DISPUTED';
  end if;
end;
$$;
grant execute on function public.confirm_return(uuid, boolean) to authenticated;

-- 8. Chat message alerts — notify the other party on a new handover message.
--    De-duplicated: one unread 'chat_message' alert per recipient at a time.
create or replace function public.notify_claim_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_finder    uuid;
  v_claimant  uuid;
  v_recipient uuid;
begin
  select finder_id, claimant_id into v_finder, v_claimant
    from claims where id = new.claim_id;
  if v_finder is null then return new; end if;

  v_recipient := case when new.sender_id = v_finder then v_claimant else v_finder end;
  if v_recipient is null or v_recipient = new.sender_id then return new; end if;

  if exists (
    select 1 from notifications
    where user_id = v_recipient and type = 'chat_message' and is_read = false
  ) then
    return new;
  end if;

  begin
    insert into notifications(user_id, title, message, item_id, is_read, type)
      values (
        v_recipient,
        'New message',
        'You have a new message about a handover. Open My Claims to reply.',
        null,
        false,
        'chat_message'
      );
  exception when others then null;
  end;

  return new;
end;
$$;

drop trigger if exists trg_notify_claim_message on public.claim_messages;
create trigger trg_notify_claim_message
  after insert on public.claim_messages
  for each row execute function public.notify_claim_message();

-- 9. Secure handover verification (QR + 6-digit code). Finder generates a
--    one-time code; the claimant must present it (scan QR or type) to prove the
--    two matched parties are together before the item changes hands.
alter table public.claims add column if not exists handover_verified boolean default false;

-- Code lives in its own table so ONLY the finder can read it (Zero-Trust).
create table if not exists public.claim_handovers (
  claim_id   uuid primary key references public.claims(id) on delete cascade,
  code       text not null,
  created_at timestamptz default now()
);
alter table public.claim_handovers enable row level security;

drop policy if exists "handover_finder_read" on public.claim_handovers;
create policy "handover_finder_read" on public.claim_handovers for select
  using (auth.uid() = (select finder_id from public.claims where id = claim_id));

create or replace function public.start_handover(p_claim_id uuid)
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

  v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  insert into claim_handovers(claim_id, code)
    values (p_claim_id, v_code)
    on conflict (claim_id) do update set code = excluded.code, created_at = now();
  return v_code;
end;
$$;
grant execute on function public.start_handover(uuid) to authenticated;

create or replace function public.verify_handover(p_claim_id uuid, p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_claimant uuid;
  v_finder   uuid;
  v_stored   text;
begin
  if v_uid is null then return 'NOT_AUTHENTICATED'; end if;
  select claimant_id, finder_id into v_claimant, v_finder
    from claims where id = p_claim_id;
  if v_claimant is null then return 'NOT_FOUND'; end if;
  if v_uid <> v_claimant then return 'NOT_CLAIMANT'; end if;

  select code into v_stored from claim_handovers where claim_id = p_claim_id;
  if v_stored is null then return 'NO_CODE'; end if;
  if btrim(p_code) <> v_stored then return 'BAD_CODE'; end if;

  update claims set handover_verified = true, updated_at = now()
    where id = p_claim_id;

  begin
    insert into notifications(user_id, title, message, item_id, is_read, type)
      values (v_finder, 'Handover verified',
        'The claimant verified the handover code — you can safely hand over the item.',
        null, false, 'handover_verified');
  exception when others then null;
  end;

  return 'OK';
end;
$$;
grant execute on function public.verify_handover(uuid, text) to authenticated;
