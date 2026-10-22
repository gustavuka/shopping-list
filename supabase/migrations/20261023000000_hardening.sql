-- Hardening for a public web deploy (ADR 0009): throttle room-password guessing, bound what one
-- account can store, keep server-owned columns server-owned, and schedule the cleanup jobs.

-- ─────────────────────────────────────────────────────────────
-- Length limits on the remaining free-text columns
-- ─────────────────────────────────────────────────────────────

update public.profiles set display_name = left(btrim(display_name), 50) where char_length(display_name) > 50;
alter table public.profiles add constraint profiles_display_name_length check (char_length(display_name) <= 50);
alter table public.lists    add constraint lists_emoji_length          check (char_length(emoji) <= 16);
alter table public.items    add constraint items_category_length       check (char_length(category) <= 32);

-- Sign-up metadata is client-controlled: truncate instead of failing the sign-up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, left(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), '')), 50));
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- Row caps (tombstones count until purged, so these bound storage)
-- ─────────────────────────────────────────────────────────────

-- security definer: counts every row, not just the ones RLS shows the caller.
create function public.enforce_row_caps() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Upserts of existing rows also fire BEFORE INSERT; only genuinely new rows count against the cap.
  if tg_table_name = 'items' then
    if not exists (select 1 from public.items where id = new.id)
       and (select count(*) from public.items where list_id = new.list_id) >= 2000 then
      raise exception 'this list is full' using errcode = 'P0001';
    end if;
  elsif not exists (select 1 from public.lists where id = new.id)
        and (select count(*) from public.lists where created_by = (select auth.uid())) >= 50 then
    raise exception 'too many lists' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger items_row_caps before insert on public.items for each row execute function public.enforce_row_caps();
create trigger lists_row_caps before insert on public.lists for each row execute function public.enforce_row_caps();
create index lists_created_by_idx on public.lists (created_by);

-- ─────────────────────────────────────────────────────────────
-- Server-owned columns
-- ─────────────────────────────────────────────────────────────

-- invite_code and has_password change only through the RPCs (security definer, so current_user is
-- the owner there); a client write can't pick its own code or flip the flag.
create or replace function public.lists_before_write() returns trigger
language plpgsql set search_path = '' as $$
declare
  from_client constant boolean := current_user in ('authenticated', 'anon');
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce((select auth.uid()), new.created_by);
    if from_client then
      new.invite_code := public.generate_invite_code();
      new.has_password := false;
    else
      new.invite_code := coalesce(new.invite_code, public.generate_invite_code());
    end if;
  else
    new.created_by := old.created_by;
    if from_client then
      new.invite_code := old.invite_code;
      new.has_password := old.has_password;
    end if;
  end if;
  return new;
end;
$$;

-- checked_by is whoever checked the item, like updated_by is whoever changed it.
create or replace function public.items_before_write() returns trigger
language plpgsql set search_path = '' as $$
declare
  me uuid := (select auth.uid());
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(me, new.created_by);
  else
    new.created_by := old.created_by;
    new.list_id := old.list_id;  -- items never move between lists
  end if;
  new.updated_by := coalesce(me, new.updated_by);
  if not new.is_checked then
    new.checked_by := null;
  elsif tg_op = 'INSERT' or not old.is_checked then
    new.checked_by := coalesce(me, new.checked_by);
  else
    new.checked_by := old.checked_by;
  end if;
  return new;
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- Room passwords: throttled joins, 6+ characters, slower hashes
-- ─────────────────────────────────────────────────────────────

-- Failed joins. RLS on, no policies: only join_list reads or writes it.
create table public.join_attempts (
  id           bigint generated always as identity primary key,
  user_id      uuid not null,
  list_id      uuid,  -- set when the code matched a room (wrong password)
  attempted_at timestamptz not null default now()
);
create index join_attempts_user_idx on public.join_attempts (user_id, attempted_at);
create index join_attempts_list_idx on public.join_attempts (list_id, attempted_at) where list_id is not null;
alter table public.join_attempts enable row level security;
revoke all on public.join_attempts from anon, authenticated;

create or replace function public.set_list_password(p_list_id uuid, p_password text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_list_member(p_list_id) then
    raise exception 'not a member of this list' using errcode = '42501';
  end if;
  if char_length(coalesce(p_password, '')) < 6 then
    raise exception 'password must have at least 6 characters' using errcode = '22023';
  end if;

  insert into public.list_secrets (list_id, password_hash)
  values (p_list_id, extensions.crypt(p_password, extensions.gen_salt('bf', 10)))
  on conflict (list_id) do update
    set password_hash = excluded.password_hash, updated_at = now();

  update public.lists set has_password = true where id = p_list_id and not has_password;
end;
$$;

-- Returns {"list": <row>} or {"error": "invalid" | "throttled"} instead of raising, because a raise
-- would roll back the recorded attempt. Wrong code and wrong password stay indistinguishable.
-- Limits: 5 failures per user per 15 min (guessing codes), 20 per room per hour (guessing a
-- password across many guest users).
drop function public.join_list(text, text);

create function public.join_list(p_invite_code text, p_password text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  target public.lists;
  secret text;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if (select count(*) from public.join_attempts
      where user_id = me and attempted_at > now() - interval '15 minutes') >= 5 then
    return jsonb_build_object('error', 'throttled');
  end if;

  select * into target from public.lists
  where invite_code = upper(btrim(p_invite_code)) and deleted_at is null;
  select password_hash into secret from public.list_secrets where list_id = target.id;

  if target.id is not null and (select count(*) from public.join_attempts
      where list_id = target.id and attempted_at > now() - interval '1 hour') >= 20 then
    return jsonb_build_object('error', 'throttled');
  end if;

  -- No room, no password set yet, or the wrong password: all the same failure.
  if secret is null or secret <> extensions.crypt(coalesce(p_password, ''), secret) then
    insert into public.join_attempts (user_id, list_id) values (me, target.id);
    return jsonb_build_object('error', 'invalid');
  end if;

  insert into public.list_members (list_id, user_id)
  values (target.id, me)
  on conflict do nothing;

  return jsonb_build_object('list', to_jsonb(target));
end;
$$;

revoke execute on function public.join_list(text, text) from public, anon;
grant  execute on function public.join_list(text, text) to authenticated;
revoke execute on function public.enforce_row_caps()    from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- Scheduled cleanup
-- ─────────────────────────────────────────────────────────────

-- Hard-deletes tombstones older than 30 days, old join attempts, and guests that never kept anything
-- (no room, no authored rows) — e.g. bulk sign-ups from the public URL.
create or replace function public.purge_tombstones() returns void
language sql security definer set search_path = '' as $$
  delete from public.items where deleted_at < now() - interval '30 days';
  delete from public.lists where deleted_at < now() - interval '30 days';
  delete from public.join_attempts where attempted_at < now() - interval '1 day';
  delete from auth.users u
  where u.is_anonymous
    and u.created_at < now() - interval '7 days'
    and not exists (select 1 from public.list_members m where m.user_id = u.id)
    and not exists (select 1 from public.lists l where l.created_by = u.id)
    and not exists (select 1 from public.items i
                    where i.created_by = u.id or i.updated_by = u.id or i.checked_by = u.id);
$$;

revoke execute on function public.purge_tombstones() from public, anon, authenticated;

create extension if not exists pg_cron;
select cron.schedule('purge-tombstones', '17 4 * * *', 'select public.purge_tombstones()');
