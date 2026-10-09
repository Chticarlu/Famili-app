-- Applied to Supabase via migration validate_legal_acceptance_membership_and_version.
-- Does not alter existing consent records, subscriptions, or Stripe.
CREATE OR REPLACE FUNCTION public.record_legal_acceptance(p_document_type text, p_document_version text, p_household_id uuid DEFAULT NULL::uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_document_type is null or p_document_type not in ('cgu_privacy','cgv_subscription') then
    raise exception 'Invalid document type';
  end if;
  if nullif(trim(p_document_version), '') is null or char_length(p_document_version) > 80 then
    raise exception 'Invalid document version';
  end if;
  if p_household_id is not null and not exists (
    select 1 from public.household_members hm
    where hm.household_id = p_household_id and hm.user_id = auth.uid()
  ) then
    raise exception 'Not a household member';
  end if;
  if p_document_type = 'cgv_subscription' then
    if p_household_id is null then raise exception 'Household required'; end if;
    if not exists (
      select 1 from public.household_members hm
      where hm.household_id = p_household_id and hm.user_id = auth.uid() and hm.role = 'owner'
    ) then
      raise exception 'Only household owner can accept subscription terms';
    end if;
  end if;
  insert into public.legal_acceptances(user_id, household_id, document_type, document_version, accepted_at)
  values(auth.uid(), p_household_id, p_document_type, p_document_version, now());
end;
$function$;
