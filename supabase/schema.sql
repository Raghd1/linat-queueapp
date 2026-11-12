-- Virtual queue schema. Run once in the Supabase SQL editor (safe to re-run).

-- Business timezone: decides when "today" starts, so the line resets at local midnight.
create or replace function queue_tz() returns text
language sql immutable as $$ select 'Asia/Riyadh' $$;  -- change to e.g. 'America/New_York'

create or replace function is_today(t timestamptz) returns boolean
language sql stable as $$
  select (t at time zone queue_tz())::date = (now() at time zone queue_tz())::date
$$;

create table if not exists entries (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 40),
  party_size int  not null check (party_size between 1 and 20),
  status     text not null default 'waiting'
             check (status in ('waiting', 'called', 'done', 'no_show')),
  created_at timestamptz not null default clock_timestamp(),  -- not now(): keeps join order exact within one transaction
  called_at  timestamptz
);
create index if not exists entries_status_created on entries (status, created_at);

-- Only the staff login can touch the table. Customers go through the functions below,
-- so they never see anyone else's name.
alter table entries enable row level security;
revoke all on entries from anon;  -- Supabase grants anon table access by default
-- Explicit, in case the project's default grants differ; RLS below still limits this to staff.
grant usage on schema public to authenticated;
grant select, insert, update, delete on entries to authenticated;

create or replace function is_staff() returns boolean
language sql stable as $$
  -- app_metadata can only be set server-side, so random sign-ups can't become staff.
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'staff'
$$;

drop policy if exists staff_all on entries;
create policy staff_all on entries for all to authenticated
  using (is_staff()) with check (is_staff());

-- Customer: join the line. Returns the ticket id (an unguessable uuid).
create or replace function join_queue(p_name text, p_party int) returns uuid
language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  p_name := btrim(p_name);
  if p_name is null or char_length(p_name) not between 1 and 40 then
    raise exception 'Name must be 1-40 characters';
  end if;
  if p_party is null or p_party not between 1 and 20 then
    raise exception 'Party size must be 1-20';
  end if;
  insert into entries (name, party_size) values (p_name, p_party) returning id into new_id;
  return new_id;
end $$;

-- Customer: my status, position and estimated wait. No row = unknown ticket.
create or replace function get_status(p_id uuid)
returns table (status text, "position" int, est_minutes int)
language plpgsql stable security definer set search_path = public as $$
declare
  e entries;
  pos int;
  avg_sec numeric;
begin
  select * into e from entries where id = p_id;
  if not found then return; end if;
  if e.status <> 'waiting' then
    return query select e.status, null::int, null::int;
    return;
  end if;

  select 1 + count(*) into pos from entries x
  where x.status = 'waiting' and is_today(x.created_at)
    and (x.created_at, x.id) < (e.created_at, e.id);

  -- Mean gap between today's last 10 calls; 5 min until there are two calls.
  -- shortcut: an idle gap (e.g. empty line at 3pm) inflates the average; cap or drop outliers if estimates feel off.
  select coalesce(extract(epoch from max(c) - min(c)) / nullif(count(*) - 1, 0), 300)
    into avg_sec
  from (select called_at c from entries
        where called_at is not null and is_today(called_at)
        order by called_at desc limit 10) t;

  return query select e.status, pos, greatest(1, round(pos * avg_sec / 60))::int;
end $$;

-- Staff: call the next waiting party. Locked so two staff clicking at once can't call the same person.
create or replace function call_next() returns setof entries
language sql as $$  -- security invoker: RLS limits this to staff
  update entries set status = 'called', called_at = now()
  where id = (select id from entries
              where status = 'waiting' and is_today(created_at)
              order by created_at, id limit 1
              for update skip locked)
  returning *
$$;

-- Live updates: tell every open page "something changed". No personal data in the message;
-- pages re-fetch what they're allowed to see.
create or replace function notify_queue() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform realtime.send('{}'::jsonb, 'changed', 'queue', false);
  return null;
end $$;

drop trigger if exists entries_changed on entries;
create trigger entries_changed after insert or update on entries
  for each statement execute function notify_queue();

revoke execute on function join_queue(text, int), get_status(uuid), call_next(), notify_queue() from public, anon, authenticated;
grant execute on function join_queue(text, int), get_status(uuid) to anon, authenticated;
grant execute on function call_next() to authenticated;
