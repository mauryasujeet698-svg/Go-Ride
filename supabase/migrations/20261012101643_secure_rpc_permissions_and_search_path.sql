-- Restrict exposed RPCs to authenticated users and hide trigger-only routines.
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.record_ride_event() from public, anon, authenticated;
revoke all on function public.bump_ride_sequence() from public, anon, authenticated;
revoke all on function public.estimate_fares(double precision,double precision,double precision,double precision) from public, anon;
grant execute on function public.estimate_fares(double precision,double precision,double precision,double precision) to authenticated;
revoke all on function public.create_ride(uuid,uuid,text,text) from public, anon;
grant execute on function public.create_ride(uuid,uuid,text,text) to authenticated;
revoke all on function public.cancel_ride(uuid,uuid,text) from public, anon;
grant execute on function public.cancel_ride(uuid,uuid,text) to authenticated;
