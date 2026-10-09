-- Applied via migration safeguard_household_ownership_transfer_lifecycle.
-- Existing households are not rewritten; lifecycle link changes only on future authorized transfers.
CREATE OR REPLACE FUNCTION public.transfer_household_ownership(p_household_id uuid, p_new_owner uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  -- Lock the current owner so concurrent transfers recheck the latest role.
  perform 1 from public.household_members
  where household_id = p_household_id and user_id = auth.uid() and role = 'owner'
  for update;
  if not found then
    raise exception 'Only the household owner can transfer ownership';
  end if;
  if p_new_owner = auth.uid() then
    raise exception 'New owner must be another household member';
  end if;
  -- A concurrent departure must not leave the household without an owner.
  perform 1 from public.household_members
  where household_id = p_household_id and user_id = p_new_owner
  for update;
  if not found then
    raise exception 'New owner must belong to the household';
  end if;
  update public.household_members set role = 'member'
  where household_id = p_household_id and user_id = auth.uid();
  update public.household_members set role = 'owner'
  where household_id = p_household_id and user_id = p_new_owner;
  -- created_by is a cascading auth.users FK: move this lifecycle link as well.
  update public.households set created_by = p_new_owner
  where id = p_household_id;
end;
$function$;
