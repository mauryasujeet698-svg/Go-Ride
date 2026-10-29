-- Operational workflows: area resolution, per-area pricing model enforcement,
-- driver subscriptions, admin review and ride financial ledger.

alter table public.service_areas
  add column if not exists center_lat double precision check (center_lat is null or center_lat between -90 and 90),
  add column if not exists center_lng double precision check (center_lng is null or center_lng between -180 and 180),
  add column if not exists coverage_radius_km double precision not null default 0 check (coverage_radius_km between 0 and 200);

alter table public.ride_quotes
  add column if not exists service_area_id uuid references public.service_areas(id) on delete restrict,
  add column if not exists business_model_snapshot text check (business_model_snapshot is null or business_model_snapshot in ('subscription','commission')),
  add column if not exists commission_bps_snapshot integer not null default 0 check (commission_bps_snapshot between 0 and 10000);

alter table public.rides
  add column if not exists service_area_id uuid references public.service_areas(id) on delete restrict,
  add column if not exists business_model_snapshot text check (business_model_snapshot is null or business_model_snapshot in ('subscription','commission')),
  add column if not exists commission_bps_snapshot integer not null default 0 check (commission_bps_snapshot between 0 and 10000);

alter table public.pricing_rules drop constraint if exists pricing_rules_category_check;
alter table public.pricing_rules add constraint pricing_rules_category_check
  check (category in ('BIKE','AUTO','MINI','SEDAN'));
alter table public.vehicles drop constraint if exists vehicles_category_check;
alter table public.vehicles add constraint vehicles_category_check
  check (category in ('BIKE','AUTO','MINI','SEDAN'));
alter table public.rides drop constraint if exists rides_category_check;
alter table public.rides add constraint rides_category_check
  check (category in ('BIKE','AUTO','MINI','SEDAN'));

insert into public.pricing_rules(category, base_fare_minor, per_km_minor, minimum_fare_minor, currency, enabled)
values ('BIKE', 1000, 800, 2000, 'INR', true)
on conflict (category) do nothing;

create index if not exists driver_applications_reviewed_by_idx
  on public.driver_applications(reviewed_by);
create index if not exists user_roles_granted_by_idx
  on public.user_roles(granted_by);
create index if not exists rides_service_area_created_idx
  on public.rides(service_area_id, created_at desc);
create index if not exists ride_quotes_service_area_created_idx
  on public.ride_quotes(service_area_id, created_at desc);

create or replace function public.estimate_fares_from_route(
  p_customer_id uuid,
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_destination_lat double precision,
  p_destination_lng double precision,
  p_distance_km double precision,
  p_eta_seconds integer
)
returns table(quote_id uuid, category text, amount_minor integer, currency char(3), eta_seconds integer, expires_at timestamptz)
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $fare$
declare
  r record;
  v_distance_km double precision;
  v_recent_quotes bigint;
  v_fare integer;
  v_area_id uuid;
  v_area_code text;
  v_model text;
  v_commission_bps integer;
  v_specific_areas integer;
begin
  if p_customer_id is null or not exists (select 1 from auth.users u where u.id = p_customer_id) then
    raise exception 'invalid_customer' using errcode = '22023';
  end if;
  if p_pickup_lat is null or p_pickup_lat not between -90 and 90
     or p_destination_lat is null or p_destination_lat not between -90 and 90
     or p_pickup_lng is null or p_pickup_lng not between -180 and 180
     or p_destination_lng is null or p_destination_lng not between -180 and 180
     or p_distance_km is null or p_distance_km < 0 or p_distance_km > 200
     or p_eta_seconds is null or p_eta_seconds < 1 or p_eta_seconds > 86400 then
    raise exception 'invalid_estimate_request' using errcode = '22023';
  end if;

  v_distance_km := 6371 * 2 * asin(sqrt(
    power(sin(radians(p_destination_lat - p_pickup_lat) / 2), 2) +
    cos(radians(p_pickup_lat)) * cos(radians(p_destination_lat)) *
    power(sin(radians(p_destination_lng - p_pickup_lng) / 2), 2)
  ));
  if p_distance_km + 0.25 < v_distance_km then
    raise exception 'route_distance_invalid' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text, 0));
  select count(*) into v_recent_quotes from public.ride_quotes
  where customer_id = p_customer_id and created_at > now() - interval '1 minute';
  if v_recent_quotes >= 60 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  select count(*) into v_specific_areas
  from public.service_areas a
  where a.active and a.code <> 'DEFAULT'
    and a.center_lat is not null and a.center_lng is not null and a.coverage_radius_km > 0;

  if v_specific_areas > 0 then
    select a.id, a.code into v_area_id, v_area_code
    from public.service_areas a
    where a.active and a.code <> 'DEFAULT'
      and a.center_lat is not null and a.center_lng is not null
      and a.coverage_radius_km > 0
      and 6371 * 2 * asin(sqrt(
        power(sin(radians(p_pickup_lat - a.center_lat) / 2), 2) +
        cos(radians(a.center_lat)) * cos(radians(p_pickup_lat)) *
        power(sin(radians(p_pickup_lng - a.center_lng) / 2), 2)
      )) <= a.coverage_radius_km
    order by (a.pincode is not null) desc, a.coverage_radius_km asc
    limit 1;
    if v_area_id is null then
      raise exception 'service_unavailable' using errcode = '22023';
    end if;
  else
    select a.id, a.code into v_area_id, v_area_code
    from public.service_areas a
    where a.code = 'DEFAULT' and a.active
    limit 1;
    if v_area_id is null then
      raise exception 'service_unavailable' using errcode = '22023';
    end if;
  end if;

  select s.business_model, s.commission_bps
    into v_model, v_commission_bps
  from public.area_business_settings s
  where s.area_id = v_area_id and s.service = 'ride' and s.active;
  if not found or v_model = 'disabled' then
    raise exception 'service_unavailable' using errcode = '22023';
  end if;

  for r in select pr.* from public.pricing_rules pr where pr.enabled order by pr.category loop
    v_fare := greatest(r.minimum_fare_minor, r.base_fare_minor + ceil(p_distance_km * r.per_km_minor)::integer);
    quote_id := gen_random_uuid();
    category := r.category;
    amount_minor := v_fare;
    currency := r.currency;
    eta_seconds := p_eta_seconds;
    expires_at := now() + interval '2 minutes';
    insert into public.ride_quotes(
      id, customer_id, pickup_lat, pickup_lng, destination_lat, destination_lng,
      category, fare_minor, currency, eta_seconds, expires_at,
      service_area_id, business_model_snapshot, commission_bps_snapshot
    )
    values (
      quote_id, p_customer_id, p_pickup_lat, p_pickup_lng, p_destination_lat, p_destination_lng,
      category, amount_minor, currency, eta_seconds, expires_at,
      v_area_id, v_model, v_commission_bps
    );
    return next;
  end loop;
end;
$fare$;
revoke all on function public.estimate_fares_from_route(uuid,double precision,double precision,double precision,double precision,double precision,integer) from public, anon;
grant execute on function public.estimate_fares_from_route(uuid,double precision,double precision,double precision,double precision,double precision,integer) to service_role;

create or replace function public.create_ride(
  p_quote_id uuid,
  p_idempotency_key uuid,
  p_pickup_label text default '',
  p_destination_label text default ''
)
returns public.rides
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $ride$
declare
  v_user uuid := auth.uid();
  q public.ride_quotes%rowtype;
  v_ride public.rides%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_idempotency_key is null or p_quote_id is null then raise exception 'invalid_request' using errcode = '22023'; end if;
  select * into v_ride from public.rides where customer_id = v_user and idempotency_key = p_idempotency_key;
  if found then return v_ride; end if;
  select * into q from public.ride_quotes where id = p_quote_id and customer_id = v_user for update;
  if not found then raise exception 'quote_not_found' using errcode = 'P0002'; end if;
  if q.expires_at <= now() then raise exception 'quote_expired' using errcode = '22023'; end if;
  if q.used_at is not null then raise exception 'quote_already_used' using errcode = '22023'; end if;
  if exists (select 1 from public.rides where customer_id = v_user and status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip')) then
    raise exception 'active_ride_exists' using errcode = '23505';
  end if;
  insert into public.rides(
    customer_id, quote_id, idempotency_key, status, seq,
    pickup_lat, pickup_lng, pickup_label, destination_lat, destination_lng, destination_label,
    category, fare_minor, currency, service_area_id, business_model_snapshot, commission_bps_snapshot
  )
  values (
    v_user, q.id, p_idempotency_key, 'searching', 1,
    q.pickup_lat, q.pickup_lng, left(coalesce(p_pickup_label,''),160),
    q.destination_lat, q.destination_lng, left(coalesce(p_destination_label,''),160),
    q.category, q.fare_minor, q.currency, q.service_area_id, q.business_model_snapshot, q.commission_bps_snapshot
  )
  returning * into v_ride;
  update public.ride_quotes set used_at = now() where id = q.id;
  return v_ride;
exception
  when unique_violation then
    select * into v_ride from public.rides where customer_id = auth.uid() and idempotency_key = p_idempotency_key;
    if found then return v_ride; end if;
    raise;
end;
$ride$;
revoke all on function public.create_ride(uuid,uuid,text,text) from public, anon;
grant execute on function public.create_ride(uuid,uuid,text,text) to authenticated;

create or replace function public.enforce_subscription_on_assignment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $assign_guard$
begin
  if new.driver_id is not null and new.driver_id is distinct from old.driver_id
     and new.business_model_snapshot = 'subscription'
     and new.service_area_id is not null
     and not exists (
       select 1 from public.driver_subscriptions s
       where s.driver_id = new.driver_id
         and s.area_id = new.service_area_id
         and s.status = 'active'
         and s.starts_at <= now()
         and s.expires_at > now()
     ) then
    raise exception 'active_subscription_required' using errcode = '42501';
  end if;
  return new;
end;
$assign_guard$;
drop trigger if exists rides_enforce_subscription_on_assignment on public.rides;
create trigger rides_enforce_subscription_on_assignment
before update of driver_id on public.rides
for each row execute function public.enforce_subscription_on_assignment();
revoke all on function public.enforce_subscription_on_assignment() from public, anon, authenticated;

create or replace function public.record_ride_financials()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $financials$
declare
  v_commission bigint;
begin
  if new.status = 'completed' and old.status is distinct from new.status
     and new.service_area_id is not null
     and new.business_model_snapshot is not null then
    v_commission := case
      when new.business_model_snapshot = 'commission'
      then floor(new.fare_minor * new.commission_bps_snapshot / 10000.0)::bigint
      else 0
    end;
    insert into public.ride_financials(
      ride_id, area_id, business_model_snapshot, fare_minor,
      commission_bps_snapshot, commission_minor, driver_net_minor, currency
    )
    values (
      new.id, new.service_area_id, new.business_model_snapshot, new.fare_minor,
      new.commission_bps_snapshot, v_commission, new.fare_minor - v_commission, new.currency
    )
    on conflict (ride_id) do nothing;
    insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
    values (new.driver_id, 'system', 'ride.financials_recorded', 'ride', new.id::text, 'success',
      jsonb_build_object('business_model', new.business_model_snapshot, 'fare_minor', new.fare_minor, 'commission_minor', v_commission));
  end if;
  return new;
end;
$financials$;
drop trigger if exists rides_record_financials on public.rides;
create trigger rides_record_financials after update of status on public.rides
for each row execute function public.record_ride_financials();
revoke all on function public.record_ride_financials() from public, anon, authenticated;

create or replace function public.driver_request_subscription(p_plan_id uuid, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $driver_request$
declare
  v_user uuid := auth.uid();
  p public.subscription_plans%rowtype;
  v_model text;
  v_existing public.driver_subscriptions%rowtype;
  v_created public.driver_subscriptions%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if not public.has_app_role('driver') then raise exception 'driver_role_required' using errcode = '42501'; end if;
  if p_idempotency_key is null or char_length(p_idempotency_key) < 16 or char_length(p_idempotency_key) > 128 then
    raise exception 'invalid_idempotency_key' using errcode = '22023';
  end if;
  select * into v_existing from public.driver_subscriptions where idempotency_key = p_idempotency_key;
  if found then
    if v_existing.driver_id <> v_user then raise exception 'idempotency_key_conflict' using errcode = '23505'; end if;
    return to_jsonb(v_existing);
  end if;
  select * into p from public.subscription_plans
  where id = p_plan_id and active and effective_from <= now()
    and exists (select 1 from public.service_areas a where a.id = subscription_plans.area_id and a.active)
  for share;
  if not found then raise exception 'subscription_plan_unavailable' using errcode = 'P0002'; end if;
  select s.business_model into v_model from public.area_business_settings s
  where s.area_id = p.area_id and s.service = 'ride' and s.active;
  if v_model <> 'subscription' then raise exception 'subscription_not_required_for_area' using errcode = '22023'; end if;
  insert into public.driver_subscriptions(
    driver_id, area_id, plan_id, status, price_minor_snapshot, currency,
    duration_minutes_snapshot, idempotency_key
  ) values (
    v_user, p.area_id, p.id, 'pending_payment', p.price_minor, p.currency,
    p.duration_minutes, p_idempotency_key
  ) returning * into v_created;
  return to_jsonb(v_created);
end;
$driver_request$;
revoke all on function public.driver_request_subscription(uuid,text) from public, anon;
grant execute on function public.driver_request_subscription(uuid,text) to authenticated;

create or replace function public.admin_activate_subscription(p_subscription_id uuid, p_payment_reference text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $activate$
declare
  v_subscription public.driver_subscriptions%rowtype;
begin
  if auth.uid() is null or not public.has_app_role('admin') then
    raise exception 'admin_role_required' using errcode = '42501';
  end if;
  if p_payment_reference is null or char_length(trim(p_payment_reference)) < 3 or char_length(p_payment_reference) > 120 then
    raise exception 'payment_reference_required' using errcode = '22023';
  end if;
  select * into v_subscription from public.driver_subscriptions where id = p_subscription_id for update;
  if not found then raise exception 'subscription_not_found' using errcode = 'P0002'; end if;
  if v_subscription.status = 'active' and v_subscription.expires_at > now() then return to_jsonb(v_subscription); end if;
  if v_subscription.status <> 'pending_payment' then raise exception 'subscription_not_pending' using errcode = '22023'; end if;
  update public.driver_subscriptions set
    status = 'active',
    starts_at = now(),
    expires_at = now() + (v_subscription.duration_minutes_snapshot * interval '1 minute'),
    payment_reference = left(trim(p_payment_reference),120)
  where id = p_subscription_id returning * into v_subscription;
  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (auth.uid(), 'admin', 'subscription.activated', 'driver_subscription', v_subscription.id::text, 'success',
    jsonb_build_object('driver_id', v_subscription.driver_id, 'area_id', v_subscription.area_id, 'price_minor', v_subscription.price_minor_snapshot));
  return to_jsonb(v_subscription);
end;
$activate$;
revoke all on function public.admin_activate_subscription(uuid,text) from public, anon;
grant execute on function public.admin_activate_subscription(uuid,text) to authenticated;

create or replace function public.driver_set_availability(p_area_id uuid, p_available boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $availability$
declare
  v_user uuid := auth.uid();
  v_model text;
  v_profile public.driver_profiles%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if not public.has_app_role('driver') then raise exception 'driver_role_required' using errcode = '42501'; end if;
  if p_available then
    select s.business_model into v_model
    from public.area_business_settings s
    join public.service_areas a on a.id = s.area_id
    where s.area_id = p_area_id and s.service = 'ride' and s.active and a.active;
    if not found or v_model = 'disabled' then raise exception 'service_unavailable' using errcode = '22023'; end if;
    if v_model = 'subscription' and not exists (
      select 1 from public.driver_subscriptions d
      where d.driver_id = v_user and d.area_id = p_area_id and d.status = 'active'
        and d.starts_at <= now() and d.expires_at > now()
    ) then raise exception 'active_subscription_required' using errcode = '42501'; end if;
    update public.driver_profiles set status = 'available' where user_id = v_user returning * into v_profile;
  else
    update public.driver_profiles set status = 'offline' where user_id = v_user returning * into v_profile;
  end if;
  if not found then raise exception 'driver_profile_missing' using errcode = 'P0002'; end if;
  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (v_user, 'driver_partner', case when p_available then 'driver.availability_on' else 'driver.availability_off' end,
    'driver_profile', v_user::text, 'success', jsonb_build_object('area_id', p_area_id));
  return to_jsonb(v_profile);
end;
$availability$;
revoke all on function public.driver_set_availability(uuid,boolean) from public, anon;
grant execute on function public.driver_set_availability(uuid,boolean) to authenticated;

create or replace function public.admin_assign_driver_to_ride(p_ride_id uuid, p_driver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $assign$
declare
  v_ride public.rides%rowtype;
  v_driver public.driver_profiles%rowtype;
begin
  if auth.uid() is null or not public.has_app_role('admin') then raise exception 'admin_role_required' using errcode = '42501'; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  if v_ride.status <> 'searching' then raise exception 'ride_not_searching' using errcode = '22023'; end if;
  select * into v_driver from public.driver_profiles where user_id = p_driver_id for share;
  if not found or v_driver.status <> 'available' then raise exception 'driver_not_available' using errcode = '22023'; end if;
  if v_ride.business_model_snapshot = 'subscription' and not exists (
    select 1 from public.driver_subscriptions s where s.driver_id = p_driver_id
      and s.area_id = v_ride.service_area_id and s.status = 'active'
      and s.starts_at <= now() and s.expires_at > now()
  ) then raise exception 'active_subscription_required' using errcode = '42501'; end if;
  update public.rides set driver_id = p_driver_id, status = 'driver_assigned'
  where id = p_ride_id returning * into v_ride;
  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (auth.uid(), 'admin', 'ride.driver_assigned', 'ride', v_ride.id::text, 'success',
    jsonb_build_object('driver_id', p_driver_id, 'service_area_id', v_ride.service_area_id));
  return to_jsonb(v_ride);
end;
$assign$;
revoke all on function public.admin_assign_driver_to_ride(uuid,uuid) from public, anon;
grant execute on function public.admin_assign_driver_to_ride(uuid,uuid) to authenticated;

create or replace function public.driver_update_ride_status(p_ride_id uuid, p_new_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $driver_status$
declare
  v_ride public.rides%rowtype;
  v_allowed boolean := false;
begin
  if auth.uid() is null or not public.has_app_role('driver') then raise exception 'driver_role_required' using errcode = '42501'; end if;
  select * into v_ride from public.rides where id = p_ride_id and driver_id = auth.uid() for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  v_allowed := (v_ride.status = 'driver_assigned' and p_new_status = 'driver_arriving')
    or (v_ride.status = 'driver_arriving' and p_new_status = 'driver_arrived')
    or (v_ride.status = 'driver_arrived' and p_new_status = 'in_trip')
    or (v_ride.status = 'in_trip' and p_new_status = 'completed');
  if not v_allowed then raise exception 'invalid_ride_status_transition' using errcode = '22023'; end if;
  update public.rides set
    status = p_new_status,
    completed_at = case when p_new_status = 'completed' then now() else completed_at end
  where id = p_ride_id returning * into v_ride;
  if p_new_status = 'in_trip' then
    update public.driver_profiles set status = 'on_trip' where user_id = auth.uid();
  elsif p_new_status = 'completed' then
    update public.driver_profiles set status = 'offline' where user_id = auth.uid();
  end if;
  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (auth.uid(), 'driver_partner', 'ride.status_updated', 'ride', v_ride.id::text, 'success',
    jsonb_build_object('status', p_new_status));
  return to_jsonb(v_ride);
end;
$driver_status$;
revoke all on function public.driver_update_ride_status(uuid,text) from public, anon;
grant execute on function public.driver_update_ride_status(uuid,text) to authenticated;

create or replace function public.admin_review_driver_application(
  p_application_id uuid,
  p_decision text,
  p_review_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $review$
declare
  v_application public.driver_applications%rowtype;
begin
  if auth.uid() is null or not public.has_app_role('admin') then raise exception 'admin_role_required' using errcode = '42501'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'invalid_decision' using errcode = '22023'; end if;
  select * into v_application from public.driver_applications where id = p_application_id for update;
  if not found then raise exception 'application_not_found' using errcode = 'P0002'; end if;
  if v_application.status not in ('pending','in_review') then raise exception 'application_already_reviewed' using errcode = '22023'; end if;

  update public.driver_applications set
    status = p_decision,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    review_note = left(coalesce(p_review_note,''),500),
    updated_at = now()
  where id = p_application_id returning * into v_application;

  if p_decision = 'approved' then
    insert into public.user_roles(user_id, role, status, granted_by, granted_at, revoked_at)
    values (v_application.user_id, 'driver', 'active', auth.uid(), now(), null)
    on conflict (user_id, role) do update
      set status = 'active', granted_by = excluded.granted_by, granted_at = now(), revoked_at = null;
    insert into public.driver_profiles(user_id, display_name, phone, status)
    values (v_application.user_id, v_application.full_name, v_application.phone, 'offline')
    on conflict (user_id) do update set display_name = excluded.display_name, phone = excluded.phone;
    insert into public.vehicles(driver_id, category, make_model, plate_number, active)
    values (v_application.user_id, v_application.vehicle_category, v_application.vehicle_make_model,
      upper(v_application.vehicle_registration), true);
  end if;

  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (auth.uid(), 'admin', case when p_decision = 'approved' then 'driver.application_approved' else 'driver.application_rejected' end,
    'driver_application', v_application.id::text, 'success',
    jsonb_build_object('decision', p_decision, 'vehicle_category', v_application.vehicle_category));
  return jsonb_build_object('id', v_application.id, 'status', v_application.status, 'reviewed_at', v_application.reviewed_at);
end;
$review$;
revoke all on function public.admin_review_driver_application(uuid,text,text) from public, anon;
grant execute on function public.admin_review_driver_application(uuid,text,text) to authenticated;

create or replace function public.admin_update_support_ticket(
  p_ticket_id uuid,
  p_status text,
  p_priority text default null,
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $support$
declare
  v_ticket public.support_tickets%rowtype;
begin
  if auth.uid() is null or not public.has_app_role('admin') then raise exception 'admin_role_required' using errcode = '42501'; end if;
  if p_status not in ('open','in_progress','resolved','closed') then raise exception 'invalid_ticket_status' using errcode = '22023'; end if;
  if p_priority is not null and p_priority not in ('low','normal','high','urgent') then raise exception 'invalid_ticket_priority' using errcode = '22023'; end if;
  select * into v_ticket from public.support_tickets where id = p_ticket_id for update;
  if not found then raise exception 'ticket_not_found' using errcode = 'P0002'; end if;
  update public.support_tickets set
    status = p_status,
    priority = coalesce(p_priority, priority),
    needs_human = case when p_status in ('resolved','closed') then false else needs_human end,
    assigned_to = coalesce(assigned_to, auth.uid()),
    updated_at = now()
  where id = p_ticket_id returning * into v_ticket;
  if char_length(trim(coalesce(p_note,''))) > 0 then
    insert into public.support_ticket_messages(ticket_id, author_id, author_type, content)
    values (p_ticket_id, auth.uid(), 'admin', left(trim(p_note),5000));
  end if;
  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (auth.uid(), 'admin', 'support.ticket_updated', 'support_ticket', p_ticket_id::text, 'success',
    jsonb_build_object('status', p_status, 'priority', v_ticket.priority, 'needs_human', v_ticket.needs_human));
  return jsonb_build_object('id', v_ticket.id, 'status', v_ticket.status, 'priority', v_ticket.priority, 'needs_human', v_ticket.needs_human);
end;
$support$;
revoke all on function public.admin_update_support_ticket(uuid,text,text,text) from public, anon;
grant execute on function public.admin_update_support_ticket(uuid,text,text,text) to authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $isadmin$
  select public.has_app_role('admin');
$isadmin$;
revoke all on function public.is_admin() from public, anon, authenticated;

drop policy if exists driver_applications_admin_read on public.driver_applications;
create policy driver_applications_admin_read on public.driver_applications
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists profiles_admin_read on public.profiles;
create policy profiles_admin_read on public.profiles
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists driver_profiles_admin_read on public.driver_profiles;
create policy driver_profiles_admin_read on public.driver_profiles
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists vehicles_admin_read on public.vehicles;
create policy vehicles_admin_read on public.vehicles
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists rides_admin_read on public.rides;
create policy rides_admin_read on public.rides
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists ride_events_admin_read on public.ride_events;
create policy ride_events_admin_read on public.ride_events
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists pricing_rules_admin_manage on public.pricing_rules;
create policy pricing_rules_admin_manage on public.pricing_rules
for all to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));

grant select on public.driver_applications, public.profiles, public.driver_profiles, public.vehicles,
  public.rides, public.ride_events, public.pricing_rules to authenticated;
grant insert, update, delete on public.pricing_rules to authenticated;

revoke all on function public.is_admin() from public, anon, authenticated;
