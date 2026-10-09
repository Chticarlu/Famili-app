-- Synthetic fixtures only. Run as postgres; every change is rolled back.
BEGIN;
CREATE TEMP TABLE invitation_test_results (test text PRIMARY KEY, passed boolean);
DO $$
DECLARE
  owner_a uuid := gen_random_uuid(); owner_b uuid := gen_random_uuid();
  member_a uuid := gen_random_uuid(); guest uuid := gen_random_uuid();
  guest2 uuid := gen_random_uuid(); guest3 uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
  legacy text := 'ABCDEF12'; code text; result jsonb; h public.households;
  i integer; denied boolean; visible integer;
BEGIN
  INSERT INTO auth.users(id,email) SELECT u, u::text||'@invitation-test.invalid'
    FROM unnest(ARRAY[owner_a,owner_b,member_a,guest,guest2,guest3]) u;
  INSERT INTO public.households(id,name,created_by,invite_code) VALUES(a,'Invitation test A',owner_a,legacy);
  INSERT INTO public.households(id,name,created_by) VALUES(b,'Invitation test B',owner_b);
  INSERT INTO public.household_members(household_id,user_id,role) VALUES(a,owner_a,'owner'),(b,owner_b,'owner'),(a,member_a,'member');
  INSERT INTO invitation_test_results SELECT 'new household: long code and 7-day expiry',
    invite_code ~ '^[0-9A-F]{32}$' AND invite_expires_at BETWEEN now()+interval '6 days 23 hours' AND now()+interval '7 days 1 hour'
    FROM public.households WHERE id=b;

  PERFORM set_config('request.jwt.claim.sub',guest::text,true);
  SET LOCAL ROLE authenticated;
  result := public.join_household_invitation('  abcdef12  ');
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('legacy code accepts trim/lowercase',result->>'status'='joined');
  INSERT INTO invitation_test_results SELECT 'joined with member role only',role='member' FROM public.household_members WHERE user_id=guest;
  SET LOCAL ROLE authenticated;
  result := public.join_household_invitation((SELECT invite_code FROM public.households WHERE id=a));
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('existing member cannot join again',result->>'status'='already_member');

  -- RLS and owner checks run under the actual authenticated role.
  PERFORM set_config('request.jwt.claim.sub',member_a::text,true);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO visible FROM public.households WHERE id=b;
  denied:=false;
  BEGIN PERFORM public.regenerate_invite_code(a); EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='Owner access required'; END;
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('foreign household invisible through RLS',visible=0),('member cannot regenerate',denied);
  SET LOCAL ROLE authenticated;
  denied:=false;
  BEGIN PERFORM public.revoke_invite_code(a); EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='Owner access required'; END;
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('member cannot revoke',denied);
  PERFORM set_config('request.jwt.claim.sub',owner_b::text,true);
  SET LOCAL ROLE authenticated;
  denied:=false;
  BEGIN PERFORM public.regenerate_invite_code(a); EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='Owner access required'; END;
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('foreign owner cannot regenerate',denied);
  SET LOCAL ROLE authenticated;
  denied:=false;
  BEGIN PERFORM public.revoke_invite_code(a); EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='Owner access required'; END;
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('foreign owner cannot revoke',denied);

  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  SET LOCAL ROLE authenticated;
  code:=public.regenerate_invite_code(a);
  RESET ROLE;
  INSERT INTO invitation_test_results SELECT 'owner regeneration replaces code and renews expiry',
    code<>legacy AND invite_code=code AND code ~ '^[0-9A-F]{32}$' AND invite_revoked_at IS NULL AND invite_expires_at>now()+interval '6 days 23 hours'
    FROM public.households WHERE id=a;
  PERFORM set_config('request.jwt.claim.sub',guest2::text,true);
  SET LOCAL ROLE authenticated;
  result:=public.join_household_invitation(legacy);
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('old regenerated code rejected',result->>'status'='invalid');
  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  SET LOCAL ROLE authenticated; PERFORM public.revoke_invite_code(a); RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',guest2::text,true);
  SET LOCAL ROLE authenticated; result:=public.join_household_invitation(code); RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('revoked code rejected',result->>'status'='invalid');
  INSERT INTO invitation_test_results SELECT 'revocation retains current members',count(*)=3 FROM public.household_members WHERE household_id=a;
  PERFORM set_config('request.jwt.claim.sub',owner_a::text,true);
  SET LOCAL ROLE authenticated; code:=public.regenerate_invite_code(a); RESET ROLE;
  INSERT INTO invitation_test_results SELECT 'regeneration clears revocation',invite_revoked_at IS NULL FROM public.households WHERE id=a;
  UPDATE public.households SET invite_expires_at=clock_timestamp()-interval '1 second' WHERE id=a;
  PERFORM set_config('request.jwt.claim.sub',guest2::text,true);
  SET LOCAL ROLE authenticated; result:=public.join_household_invitation(code); RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('expired code rejected',result->>'status'='invalid');
  UPDATE public.households SET invite_expires_at=clock_timestamp()+interval '7 days' WHERE id=a;
  SET LOCAL ROLE authenticated; h:=public.join_household_by_code(lower(code)); RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('legacy RPC accepts new long code',h.id=a);

  PERFORM set_config('request.jwt.claim.sub',guest3::text,true);
  SET LOCAL ROLE authenticated;
  FOR i IN 1..5 LOOP result:=public.join_household_invitation('INVALID'); END LOOP;
  result:=public.join_household_invitation(code);
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('sixth attempt blocks even valid code',result->>'status'='rate_limited' AND (result->>'retry_after_seconds')::integer BETWEEN 1 AND 900);
  INSERT INTO invitation_test_results SELECT 'invalid attempts persist counter',short_count=5 AND long_count=5 FROM private.invitation_attempts WHERE user_id=guest3;
  SET LOCAL ROLE authenticated; h:=public.join_household_by_code(code); RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('legacy RPC cannot bypass limit',h.id IS NULL);
  INSERT INTO invitation_test_results SELECT 'blocked requests do not extend window',short_count=5 FROM private.invitation_attempts WHERE user_id=guest3;
  UPDATE private.invitation_attempts SET short_started_at=now()-interval '16 minutes' WHERE user_id=guest3;
  SET LOCAL ROLE authenticated; result:=public.join_household_invitation(NULL); RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('short window resets; null rejected',result->>'status'='invalid');
  UPDATE private.invitation_attempts SET short_started_at=now()-interval '16 minutes',long_count=20 WHERE user_id=guest3;
  SET LOCAL ROLE authenticated; result:=public.join_household_invitation(code); RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('daily limit enforced',result->>'status'='rate_limited' AND (result->>'retry_after_seconds')::integer>900);
  UPDATE private.invitation_attempts SET long_started_at=now()-interval '25 hours' WHERE user_id=guest3;
  SET LOCAL ROLE authenticated; result:=public.join_household_invitation(lower(code)); RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('daily reset permits authorized join',result->>'status'='joined');

  INSERT INTO invitation_test_results VALUES
    ('anon cannot call either join RPC',NOT has_function_privilege('anon','public.join_household_invitation(text)','execute') AND NOT has_function_privilege('anon','public.join_household_by_code(text)','execute')),
    ('anon cannot revoke or regenerate',NOT has_function_privilege('anon','public.revoke_invite_code(uuid)','execute') AND NOT has_function_privilege('anon','public.regenerate_invite_code(uuid)','execute')),
    ('attempt table inaccessible',NOT has_table_privilege('authenticated','private.invitation_attempts','select') AND NOT has_table_privilege('authenticated','private.invitation_attempts','update'));
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE authenticated;
  denied:=false;
  BEGIN PERFORM public.join_household_invitation(code); EXCEPTION WHEN OTHERS THEN denied:=SQLERRM='Not authenticated'; END;
  RESET ROLE;
  INSERT INTO invitation_test_results VALUES ('missing uid refused',denied);
  IF EXISTS(SELECT 1 FROM invitation_test_results WHERE passed IS DISTINCT FROM true) THEN
    RAISE EXCEPTION 'Invitation test failed';
  END IF;
END;
$$;
SELECT * FROM invitation_test_results ORDER BY test;
ROLLBACK;
