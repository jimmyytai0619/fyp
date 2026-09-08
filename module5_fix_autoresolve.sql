-- ─────────────────────────────────────────────────────────────────────────────
-- Fix: confirming a return closed too many lost reports
-- ─────────────────────────────────────────────────────────────────────────────
-- confirm_return() resolved EVERY unresolved lost report belonging to the
-- claimant in the same category:
--
--     update lost_items set is_resolved = true
--       where user_id = v_claimant and category = v_category
--         and coalesce(is_resolved, false) = false;
--
-- "Other" is a catch-all, so confirming one return closed all of that user's
-- other "Other" reports as well. That matters because /ingest-found skips
-- resolved reports entirely, so those lost items silently stopped receiving
-- match alerts — the owner would never be told their item had been found.
--
-- Now it closes at most ONE report: the claimant's most recent unresolved
-- report in that category that already existed when the claim was created.
-- Anything filed later is left active.
--
-- Everything else in the function is unchanged.
-- Run this in the Supabase SQL Editor, AFTER module5_schema.sql.

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
  v_claim_at timestamptz;
begin
  if v_uid is null then return 'NOT_AUTHENTICATED'; end if;
  select c.finder_id, c.claimant_id, c.found_item_id, fi.category, c.created_at
    into v_finder, v_claimant, v_item, v_category, v_claim_at
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

    -- Close only the one report this return most plausibly answers, and never
    -- a report filed after the claim began.
    begin
      update lost_items set is_resolved = true
        where id = (
          select id from lost_items
           where user_id = v_claimant
             and category = v_category
             and coalesce(is_resolved, false) = false
             and created_at <= coalesce(v_claim_at, now())
           order by created_at desc
           limit 1
        );
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
