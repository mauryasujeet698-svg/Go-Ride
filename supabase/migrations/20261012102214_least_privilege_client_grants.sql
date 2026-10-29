-- Remove default PUBLIC-schema table privileges, then grant only operations
-- needed by the customer client. RLS remains the row-level boundary.
revoke all privileges on all tables in schema public from anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.driver_profiles, public.vehicles, public.pricing_rules,
  public.ride_quotes, public.rides, public.ride_events to authenticated;
grant select, insert, update, delete on public.saved_places to authenticated;
grant select, insert on public.support_tickets to authenticated;

revoke all privileges on all sequences in schema public from anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.record_ride_event() from public, anon, authenticated;
revoke all on function public.bump_ride_sequence() from public, anon, authenticated;
revoke all on function public.estimate_fares(double precision,double precision,double precision,double precision) from public, anon;
grant execute on function public.estimate_fares(double precision,double precision,double precision,double precision) to authenticated;
revoke all on function public.create_ride(uuid,uuid,text,text) from public, anon;
grant execute on function public.create_ride(uuid,uuid,text,text) to authenticated;
revoke all on function public.cancel_ride(uuid,uuid,text) from public, anon;
grant execute on function public.cancel_ride(uuid,uuid,text) to authenticated;
create index if not exists ride_quotes_customer_created_idx
  on public.ride_quotes(customer_id, created_at desc);
