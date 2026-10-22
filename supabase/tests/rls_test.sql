-- Access rules and triggers. Run with: supabase test db
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

-- Three users: Gus and Ana share a household, Eve is a stranger.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'gus@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'ana@example.com'),
  ('00000000-0000-0000-0000-00000000000e', 'eve@example.com');

select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  'gus', 'profile is auto-created from the email');

create function pg_temp.act_as(uid uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
$$;

-- ── Gus creates a list and an item ──
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');

insert into public.lists (id, name, created_by)
values ('11111111-1111-1111-1111-111111111111', 'Groceries', '00000000-0000-0000-0000-00000000000a');

select is((select count(*)::int from public.list_members where list_id = '11111111-1111-1111-1111-111111111111'),
  1, 'creator is auto-added as member');

select matches((select invite_code from public.lists where id = '11111111-1111-1111-1111-111111111111'),
  '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$', 'invite code is generated without ambiguous chars');

insert into public.items (id, list_id, name, created_by, updated_by, updated_at)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Milk',
        '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', '2000-01-01');

select isnt((select updated_at from public.items where id = '22222222-2222-2222-2222-222222222222'),
  '2000-01-01'::timestamptz, 'updated_at is set by the server, ignoring the client value');

-- ── Eve sees nothing and can't write ──
select pg_temp.act_as('00000000-0000-0000-0000-00000000000e');

select is((select count(*)::int from public.lists), 0, 'stranger cannot see the list');
select is((select count(*)::int from public.items), 0, 'stranger cannot see items');

select throws_ok(
  $$ insert into public.items (id, list_id, name, created_by, updated_by)
     values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'Hack',
             '00000000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-00000000000e') $$,
  '42501', null, 'stranger cannot insert items');

update public.items set name = 'Hacked' where id = '22222222-2222-2222-2222-222222222222';
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
select is((select name from public.items where id = '22222222-2222-2222-2222-222222222222'),
  'Milk', 'stranger update affects no rows');

select is(public.join_list('NOPE99', 'whatever'), '{"error": "invalid"}'::jsonb, 'unknown code is rejected');

-- ── Rooms need a password before anyone can join ──
create temp table code as select invite_code from public.lists where id = '11111111-1111-1111-1111-111111111111';
grant select on code to authenticated;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000e');
select is(public.join_list((select invite_code from code), ''), '{"error": "invalid"}'::jsonb,
  'a room without a password cannot be joined');
select throws_ok($$ select public.set_list_password('11111111-1111-1111-1111-111111111111', 'hunter22') $$,
  '42501', null, 'a non-member cannot set the password');

select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
select throws_ok($$ select public.set_list_password('11111111-1111-1111-1111-111111111111', 'abc') $$,
  '22023', null, 'passwords need at least 6 characters');
select throws_ok($$ select public.set_list_password('11111111-1111-1111-1111-111111111111', 'abcde') $$,
  '22023', null, '5 characters are not enough');
select lives_ok($$ select public.set_list_password('11111111-1111-1111-1111-111111111111', 'pao-de-queijo') $$, 'a member sets the room password');
select is((select has_password from public.lists where id = '11111111-1111-1111-1111-111111111111'), true, 'has_password flag is set');
select throws_ok($$ select * from public.list_secrets $$, '42501', null, 'password hashes are unreadable by clients');

-- ── Ana joins with code + password ──
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b');
select is(public.join_list((select invite_code from code), 'pao-de-ló'), '{"error": "invalid"}'::jsonb,
  'wrong password gives the same result as a wrong code');
select is((select public.join_list(lower(invite_code), 'pao-de-queijo') -> 'list' ->> 'id' from code),
  '11111111-1111-1111-1111-111111111111', 'join with code (case-insensitive) + password');
select is((select public.join_list(invite_code, 'pao-de-queijo') -> 'list' ->> 'has_password' from code),
  'true', 'joining twice is idempotent and returns the list row');
select throws_ok($$ select * from public.join_attempts $$, '42501', null, 'join attempts are unreadable by clients');

-- Members can't pick the invite code or clear the password flag; only the RPCs change them.
update public.lists set invite_code = 'AAAAAA', has_password = false where id = '11111111-1111-1111-1111-111111111111';
select is((select invite_code = (select invite_code from code) and has_password from public.lists
           where id = '11111111-1111-1111-1111-111111111111'), true, 'invite_code and has_password are server-owned');

select is((select count(*)::int from public.items), 1, 'member sees items');
select is((select count(*)::int from public.profiles), 2, 'member sees self and partner profile');

-- Ana checks the milk; the server records her as the author.
update public.items set is_checked = true, updated_by = '00000000-0000-0000-0000-00000000000a',
                        created_by = '00000000-0000-0000-0000-00000000000b'
where id = '22222222-2222-2222-2222-222222222222';

select is((select updated_by from public.items where id = '22222222-2222-2222-2222-222222222222'),
  '00000000-0000-0000-0000-00000000000b'::uuid, 'updated_by is always the caller');
select is((select created_by from public.items where id = '22222222-2222-2222-2222-222222222222'),
  '00000000-0000-0000-0000-00000000000a'::uuid, 'created_by is immutable');
select is((select checked_by from public.items where id = '22222222-2222-2222-2222-222222222222'),
  '00000000-0000-0000-0000-00000000000b'::uuid, 'checked_by is whoever checked it');

select throws_ok($$ update public.profiles set display_name = repeat('x', 51) where id = '00000000-0000-0000-0000-00000000000b' $$,
  '23514', null, 'display names are at most 50 characters');
select throws_ok($$ update public.items set category = repeat('x', 33) where id = '22222222-2222-2222-2222-222222222222' $$,
  '23514', null, 'categories are at most 32 characters');

-- The app writes with upsert (insert … on conflict do update); a partner's upsert of an existing row works
-- and keeps the original creator.
insert into public.items (id, list_id, name, created_by, updated_by)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Oat milk',
        '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b')
on conflict (id) do update set name = excluded.name, created_by = excluded.created_by;
select is((select name || ' by ' || created_by::text from public.items where id = '22222222-2222-2222-2222-222222222222'),
  'Oat milk by 00000000-0000-0000-0000-00000000000a', 'partner upsert updates the row and keeps the creator');

-- Soft delete works through update; hard delete is not allowed.
delete from public.items where id = '22222222-2222-2222-2222-222222222222';
select is((select count(*)::int from public.items), 1, 'hard delete affects no rows');

update public.items set deleted_at = now() where id = '22222222-2222-2222-2222-222222222222';
select isnt((select deleted_at from public.items where id = '22222222-2222-2222-2222-222222222222'),
  null, 'soft delete via deleted_at');

-- ── Guessing is throttled ──
-- Eve already failed once (the passwordless room). Four more failures, then even the right password is refused.
select pg_temp.act_as('00000000-0000-0000-0000-00000000000e');
select public.join_list((select invite_code from code), 'guess-' || n) from generate_series(1, 4) n;
select is(public.join_list((select invite_code from code), 'pao-de-queijo'), '{"error": "throttled"}'::jsonb,
  'five failures in 15 minutes lock the user out');
select is((select count(*)::int from public.lists), 0, 'a throttled user does not join');

-- Many guests guessing one room: 20 failures per room per hour lock the room for everyone.
reset role;
insert into public.join_attempts (user_id, list_id)
select gen_random_uuid(), '11111111-1111-1111-1111-111111111111' from generate_series(1, 20);
insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000f', 'fay@example.com');
select pg_temp.act_as('00000000-0000-0000-0000-00000000000f');
select is(public.join_list((select invite_code from code), 'pao-de-queijo'), '{"error": "throttled"}'::jsonb,
  'a room under attack refuses joins for an hour');

-- ── Caps ──
reset role;
insert into public.items (id, list_id, name, created_by, updated_by)
select gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'Filler ' || n,
       '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a'
from generate_series(1, 1999) n;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a');
select throws_ok(
  $$ insert into public.items (id, list_id, name, created_by, updated_by)
     values (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'One too many',
             '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a') $$,
  'P0001', 'this list is full', 'a list holds at most 2000 items, tombstones included');
select lives_ok(
  $$ insert into public.items (id, list_id, name, created_by, updated_by)
     values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Milk again',
             '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a')
     on conflict (id) do update set name = excluded.name $$,
  'a full list still accepts upserts of existing items');

insert into public.lists (id, name, created_by, invite_code)
values (gen_random_uuid(), 'Vanity', '00000000-0000-0000-0000-00000000000a', 'ZZZZZZ');
insert into public.lists (id, name, created_by)
select gen_random_uuid(), 'List ' || n, '00000000-0000-0000-0000-00000000000a' from generate_series(1, 48) n;
select throws_ok(
  $$ insert into public.lists (id, name, created_by) values (gen_random_uuid(), 'One too many', '00000000-0000-0000-0000-00000000000a') $$,
  'P0001', 'too many lists', 'a user creates at most 50 lists');
select isnt((select invite_code from public.lists where name = 'Vanity'), 'ZZZZZZ',
  'clients never choose their invite code on insert');

-- Anonymous users get nothing.
select set_config('role', 'anon', true);
select throws_ok($$ select * from public.items $$, '42501', null, 'anon has no table access');

select * from finish();
rollback;
