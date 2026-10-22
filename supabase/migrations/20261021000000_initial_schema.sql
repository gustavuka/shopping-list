-- Initial schema: profiles, lists, list_members, items + RLS, triggers, RPCs, realtime.
-- See docs/data-model.md and docs/sync.md.

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

-- Server clock is authoritative for updated_at; the author is always the caller.
create function public.touch_row() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

-- 6 chars, no ambiguous characters (0 O 1 I L).
create function public.generate_invite_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.lists where invite_code = code);
  end loop;
  return code;
end;
$$;

-- ─────────────────────────────────────────────────────────────
-- profiles
-- ─────────────────────────────────────────────────────────────

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  created_at   timestamptz not null default now()
);

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1), ''));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─────────────────────────────────────────────────────────────
-- lists
-- ─────────────────────────────────────────────────────────────

create table public.lists (
  id          uuid primary key,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  emoji       text,
  invite_code text not null unique,
  created_by  uuid not null references public.profiles (id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create function public.lists_before_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce((select auth.uid()), new.created_by);
    new.invite_code := coalesce(new.invite_code, public.generate_invite_code());
  else
    new.created_by := old.created_by;
  end if;
  return new;
end;
$$;

create trigger lists_before_write
  before insert or update on public.lists
  for each row execute function public.lists_before_write();

create trigger lists_touch
  before insert or update on public.lists
  for each row execute function public.touch_row();

-- ─────────────────────────────────────────────────────────────
-- list_members
-- ─────────────────────────────────────────────────────────────

create table public.list_members (
  list_id   uuid not null references public.lists (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (list_id, user_id)
);

create index list_members_user_id_idx on public.list_members (user_id);

-- The creator of a list is its first member.
create function public.add_creator_as_member() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.list_members (list_id, user_id)
  values (new.id, new.created_by)
  on conflict do nothing;
  return new;
end;
$$;

create trigger lists_add_creator
  after insert on public.lists
  for each row execute function public.add_creator_as_member();

-- security definer so policies on list_members don't recurse into themselves.
create function public.is_list_member(p_list_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.list_members
    where list_id = p_list_id and user_id = (select auth.uid())
  );
$$;

-- ─────────────────────────────────────────────────────────────
-- items
-- ─────────────────────────────────────────────────────────────

create table public.items (
  id         uuid primary key,
  list_id    uuid not null references public.lists (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 100),
  quantity   text check (char_length(quantity) <= 40),
  note       text check (char_length(note) <= 500),
  category   text not null default 'other',
  position   double precision not null default 0,
  is_checked boolean not null default false,
  checked_by uuid references public.profiles (id),
  checked_at timestamptz,
  created_by uuid not null references public.profiles (id),
  updated_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index items_list_id_updated_at_idx on public.items (list_id, updated_at);

create function public.items_before_write() returns trigger
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
  return new;
end;
$$;

create trigger items_before_write
  before insert or update on public.items
  for each row execute function public.items_before_write();

create trigger items_touch
  before insert or update on public.items
  for each row execute function public.touch_row();

-- ─────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────

alter table public.profiles     enable row level security;
alter table public.lists        enable row level security;
alter table public.list_members enable row level security;
alter table public.items        enable row level security;

create policy "profiles: read self and list partners" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.list_members mine
      join public.list_members theirs on theirs.list_id = mine.list_id
      where mine.user_id = (select auth.uid()) and theirs.user_id = profiles.id
    )
  );

create policy "profiles: update self" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- created_by check lets INSERT ... RETURNING see the row before the member trigger's insert is visible.
create policy "lists: members read" on public.lists
  for select to authenticated
  using (created_by = (select auth.uid()) or public.is_list_member(id));

create policy "lists: create own" on public.lists
  for insert to authenticated
  with check (created_by = (select auth.uid()));

create policy "lists: members update" on public.lists
  for update to authenticated
  using (public.is_list_member(id))
  with check (public.is_list_member(id));

create policy "list_members: members read" on public.list_members
  for select to authenticated
  using (public.is_list_member(list_id));

create policy "list_members: leave" on public.list_members
  for delete to authenticated
  using (user_id = (select auth.uid()));

create policy "items: members read" on public.items
  for select to authenticated
  using (public.is_list_member(list_id));

create policy "items: members create" on public.items
  for insert to authenticated
  with check (public.is_list_member(list_id) and created_by = (select auth.uid()));

create policy "items: members update" on public.items
  for update to authenticated
  using (public.is_list_member(list_id))
  with check (public.is_list_member(list_id));

-- No delete policies on lists/items: deletes are soft (deleted_at), see docs/data-model.md.

revoke all on public.profiles, public.lists, public.list_members, public.items from anon;

-- ─────────────────────────────────────────────────────────────
-- RPCs
-- ─────────────────────────────────────────────────────────────

create function public.join_list(p_invite_code text) returns public.lists
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  target public.lists;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into target from public.lists
  where invite_code = upper(btrim(p_invite_code)) and deleted_at is null;

  if not found then
    raise exception 'invalid invite code' using errcode = 'P0002';
  end if;

  insert into public.list_members (list_id, user_id)
  values (target.id, me)
  on conflict do nothing;

  return target;
end;
$$;

create function public.regenerate_invite_code(p_list_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  code text;
begin
  if not public.is_list_member(p_list_id) then
    raise exception 'not a member of this list' using errcode = '42501';
  end if;

  code := public.generate_invite_code();
  update public.lists set invite_code = code where id = p_list_id;
  return code;
end;
$$;

-- Hard-delete tombstones older than 30 days. Schedule with pg_cron on the hosted project.
create function public.purge_tombstones() returns void
language sql security definer set search_path = '' as $$
  delete from public.items where deleted_at < now() - interval '30 days';
  delete from public.lists where deleted_at < now() - interval '30 days';
$$;

revoke execute on function public.join_list(text)               from public, anon;
revoke execute on function public.regenerate_invite_code(uuid)  from public, anon;
revoke execute on function public.purge_tombstones()            from public, anon, authenticated;
revoke execute on function public.is_list_member(uuid)          from public, anon;
grant  execute on function public.join_list(text)               to authenticated;
grant  execute on function public.regenerate_invite_code(uuid)  to authenticated;
grant  execute on function public.is_list_member(uuid)          to authenticated;

-- ─────────────────────────────────────────────────────────────
-- Realtime
-- ─────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.items, public.lists;
