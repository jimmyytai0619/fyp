-- ============================================================
--  Incremental patch — Claim-request notifications
--  Safe to run on an EXISTING database: it does NOT drop any
--  tables or delete data. Run this whole file in the Supabase
--  SQL Editor once.
--
--  What it does:
--   1. Adds a `type` column to notifications so the app can tell
--      a claim request apart from an AI match alert.
--   2. Updates submit_claim() so that when a claimant passes the
--      ownership question, the FINDER gets a 'claim_request'
--      notification — no need to keep opening the Requests tab.
-- ============================================================

-- 1. Notification type tag (nullable; existing rows stay NULL = match alert).
alter table public.notifications add column if not exists type text;

-- 2. Recreate submit_claim with the finder notification on a passed quiz.
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
