-- Existing codes are unchanged and receive a 30-day transition period.
ALTER TABLE public.households
  ADD COLUMN invite_expires_at timestamptz NOT NULL DEFAULT (now() + interval '30 days'),
  ADD COLUMN invite_revoked_at timestamptz;
ALTER TABLE public.households ALTER COLUMN invite_expires_at SET DEFAULT (now() + interval '7 days');
ALTER TABLE public.households ALTER COLUMN invite_code SET DEFAULT upper(replace(gen_random_uuid()::text, '-', ''));

-- No codes or IP addresses are retained. At most one row per account.
CREATE TABLE private.invitation_attempts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  short_started_at timestamptz NOT NULL,
  short_count integer NOT NULL,
  long_started_at timestamptz NOT NULL,
  long_count integer NOT NULL
);
ALTER TABLE private.invitation_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.invitation_attempts FROM PUBLIC, anon, authenticated;

-- Rejections return a result, not an exception: otherwise Postgres rolls back
-- the attempt counter. Both the legacy RPC and the new UI use this same path.
CREATE FUNCTION public.join_household_invitation(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_attempt private.invitation_attempts;
  v_household public.households;
  v_wait integer := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- Serialize requests from one account, including concurrent legacy calls.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_uid::text, 79261));
  v_now := clock_timestamp();
  IF EXISTS (SELECT 1 FROM public.household_members WHERE user_id = v_uid) THEN
    RETURN jsonb_build_object('status', 'already_member');
  END IF;
  INSERT INTO private.invitation_attempts VALUES (v_uid, v_now, 0, v_now, 0)
    ON CONFLICT (user_id) DO NOTHING;
  SELECT * INTO v_attempt FROM private.invitation_attempts WHERE user_id = v_uid FOR UPDATE;
  IF v_now >= v_attempt.short_started_at + interval '15 minutes' THEN
    v_attempt.short_started_at := v_now; v_attempt.short_count := 0;
  END IF;
  IF v_now >= v_attempt.long_started_at + interval '24 hours' THEN
    v_attempt.long_started_at := v_now; v_attempt.long_count := 0;
  END IF;
  IF v_attempt.short_count >= 5 THEN
    v_wait := greatest(1, ceil(extract(epoch FROM v_attempt.short_started_at + interval '15 minutes' - v_now))::integer);
  END IF;
  IF v_attempt.long_count >= 20 THEN
    v_wait := greatest(v_wait, ceil(extract(epoch FROM v_attempt.long_started_at + interval '24 hours' - v_now))::integer);
  END IF;
  IF v_wait > 0 THEN
    RETURN jsonb_build_object('status', 'rate_limited', 'retry_after_seconds', v_wait);
  END IF;
  UPDATE private.invitation_attempts SET
    short_started_at = v_attempt.short_started_at, short_count = v_attempt.short_count + 1,
    long_started_at = v_attempt.long_started_at, long_count = v_attempt.long_count + 1
    WHERE user_id = v_uid;
  IF p_code IS NULL OR length(p_code) > 128 OR upper(trim(p_code)) !~ '^([0-9A-F]{8}|[0-9A-F]{32})$' THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;
  -- Same row lock as revocation/regeneration: whichever locks first wins.
  SELECT * INTO v_household FROM public.households
    WHERE invite_code = upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND OR v_household.invite_revoked_at IS NOT NULL OR v_household.invite_expires_at <= clock_timestamp() THEN
    RETURN jsonb_build_object('status', 'invalid');
  END IF;
  BEGIN
    INSERT INTO public.household_members(household_id, user_id, role)
      VALUES (v_household.id, v_uid, 'member');
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('status', 'already_member');
  END;
  RETURN jsonb_build_object('status', 'joined', 'household', to_jsonb(v_household));
END;
$$;

CREATE OR REPLACE FUNCTION public.join_household_by_code(p_code text)
RETURNS public.households LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_result jsonb;
BEGIN
  v_result := public.join_household_invitation(p_code);
  IF v_result->>'status' = 'joined' THEN
    RETURN jsonb_populate_record(NULL::public.households, v_result->'household');
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.regenerate_invite_code(p_household_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_code text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- Lock owner first, matching ownership transfer lock order.
  PERFORM 1 FROM public.household_members
    WHERE household_id = p_household_id AND user_id = auth.uid() AND role = 'owner' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Owner access required'; END IF;
  v_code := upper(replace(gen_random_uuid()::text, '-', ''));
  UPDATE public.households SET invite_code = v_code,
    invite_expires_at = clock_timestamp() + interval '7 days', invite_revoked_at = NULL
    WHERE id = p_household_id;
  RETURN v_code;
END;
$$;

CREATE FUNCTION public.revoke_invite_code(p_household_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM 1 FROM public.household_members
    WHERE household_id = p_household_id AND user_id = auth.uid() AND role = 'owner' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Owner access required'; END IF;
  UPDATE public.households SET invite_revoked_at = clock_timestamp() WHERE id = p_household_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.join_household_invitation(text), public.join_household_by_code(text),
  public.regenerate_invite_code(uuid), public.revoke_invite_code(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_household_invitation(text), public.join_household_by_code(text),
  public.regenerate_invite_code(uuid), public.revoke_invite_code(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
