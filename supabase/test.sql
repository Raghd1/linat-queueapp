-- Self-check for schema.sql. Run in the Supabase SQL editor.
-- Everything happens inside a transaction that is rolled back, so real data is untouched.
-- Success: "ALL TESTS PASSED" notice. Failure: an error naming the broken check.
begin;

do $$
declare
  a uuid; b uuid; c uuid;
  s record;
  n int;
begin
  delete from entries;  -- rolled back at the end

  -- joining + positions
  a := join_queue('  Ana  ', 2);
  b := join_queue('Ben', 4);
  c := join_queue('Cy', 1);
  assert (select name from entries where id = a) = 'Ana', 'name is trimmed';
  select * into s from get_status(b);
  assert s.status = 'waiting' and s."position" = 2, 'Ben is #2';
  assert s.est_minutes = 10, 'default estimate: 2 x 5 min';

  -- input validation
  begin perform join_queue('', 2); assert false, 'empty name rejected';
  exception when raise_exception then null; end;
  begin perform join_queue(repeat('x', 41), 2); assert false, 'long name rejected';
  exception when raise_exception then null; end;
  begin perform join_queue('Dee', 0); assert false, 'party 0 rejected';
  exception when raise_exception then null; end;
  begin perform join_queue('Dee', 21); assert false, 'party 21 rejected';
  exception when raise_exception then null; end;

  -- calling moves people up (run as postgres, so RLS is bypassed here)
  perform call_next();
  select * into s from get_status(a);
  assert s.status = 'called' and s."position" is null, 'Ana is called';
  select * into s from get_status(b);
  assert s."position" = 1, 'Ben moved to #1';

  -- learned estimate: calls 10 min apart -> 10 min per party
  update entries set called_at = now() - interval '20 minutes' where id = a;
  insert into entries (name, party_size, status, called_at) values
    ('Old1', 1, 'done', now() - interval '10 minutes'),
    ('Old2', 1, 'done', now());
  select * into s from get_status(c);  -- Cy is #2
  assert s."position" = 2 and s.est_minutes = 20, 'learned estimate: 2 x 10 min';

  -- unknown ticket
  select count(*) into n from get_status(gen_random_uuid());
  assert n = 0, 'unknown ticket returns no row';

  -- customers (anon) cannot read the table or call next
  set local role anon;
  begin perform 1 from entries; assert false, 'anon cannot select entries';
  exception when insufficient_privilege then null; end;
  begin perform call_next(); assert false, 'anon cannot call_next';
  exception when insufficient_privilege then null; end;
  select * into s from get_status(c);
  assert s."position" = 2, 'anon can still check own status';
  reset role;

  raise notice 'ALL TESTS PASSED';
end $$;

rollback;
