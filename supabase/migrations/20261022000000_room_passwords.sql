-- Rooms: a list is joined with its invite code + a password chosen by a member.
-- Users are anonymous (guest) Supabase users; see docs/decisions/0007-guest-users-and-room-passwords.md.

-- Password hashes live in their own table: RLS on, no policies, so no client can ever read them.
-- Only the security-definer functions below touch it.
create table public.list_secrets (
  list_id       uuid primary key references public.lists (id) on delete cascade,
  password_hash text not null,
  updated_at    timestamptz not null default now()
);
alter table public.list_secrets enable row level security;
revoke all on public.list_secrets from anon, authenticated;

-- Lets members see whether the room can be joined yet (drives the "set a password" step).
alter table public.lists add column has_password boolean not null default false;

create function public.set_list_password(p_list_id uuid, p_password text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_list_member(p_list_id) then
    raise exception 'not a member of this list' using errcode = '42501';
  end if;
  if char_length(coalesce(p_password, '')) < 4 then
    raise exception 'password must have at least 4 characters' using errcode = '22023';
  end if;

  insert into public.list_secrets (list_id, password_hash)
  values (p_list_id, extensions.crypt(p_password, extensions.gen_salt('bf')))
  on conflict (list_id) do update
    set password_hash = excluded.password_hash, updated_at = now();

  update public.lists set has_password = true where id = p_list_id and not has_password;
end;
$$;

-- Replaces the code-only join. Wrong code and wrong password give the same error on purpose.
drop function public.join_list(text);

create function public.join_list(p_invite_code text, p_password text) returns public.lists
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := (select auth.uid());
  target public.lists;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select l.* into target
  from public.lists l
  join public.list_secrets s on s.list_id = l.id
  where l.invite_code = upper(btrim(p_invite_code))
    and l.deleted_at is null
    and s.password_hash = extensions.crypt(coalesce(p_password, ''), s.password_hash);

  if not found then
    raise exception 'invalid code or password' using errcode = 'P0002';
  end if;

  insert into public.list_members (list_id, user_id)
  values (target.id, me)
  on conflict do nothing;

  return target;
end;
$$;

revoke execute on function public.join_list(text, text)          from public, anon;
revoke execute on function public.set_list_password(uuid, text)  from public, anon;
grant  execute on function public.join_list(text, text)          to authenticated;
grant  execute on function public.set_list_password(uuid, text)  to authenticated;
