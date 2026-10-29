alter table public.area_business_settings
  add column if not exists auto_dispatch_enabled boolean not null default true,
  add column if not exists dispatch_radius_km numeric(6,2) not null default 10;

alter table public.area_business_settings
  drop constraint if exists area_business_settings_dispatch_radius_check;
alter table public.area_business_settings
  add constraint area_business_settings_dispatch_radius_check
  check (dispatch_radius_km >= 0.5 and dispatch_radius_km <= 100);

alter table public.driver_profiles
  add column if not exists current_area_id uuid references public.service_areas(id) on delete set null,
  add column if not exists current_latitude double precision,
  add column if not exists current_longitude double precision,
  add column if not exists last_location_at timestamptz;

alter table public.driver_profiles
  drop constraint if exists driver_profiles_current_latitude_check;
alter table public.driver_profiles
  add constraint driver_profiles_current_latitude_check
  check (current_latitude is null or current_latitude between -90 and 90);
alter table public.driver_profiles
  drop constraint if exists driver_profiles_current_longitude_check;
alter table public.driver_profiles
  add constraint driver_profiles_current_longitude_check
  check (current_longitude is null or current_longitude between -180 and 180);

create index if not exists driver_profiles_available_area_location_idx
  on public.driver_profiles(current_area_id, status, last_location_at desc)
  where current_latitude is not null and current_longitude is not null;
create index if not exists vehicles_active_driver_category_idx
  on public.vehicles(driver_id, category)
  where active;

create table if not exists public.ride_dispatch_attempts (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  driver_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'offered'
    check (status in ('offered','accepted','declined','expired','cancelled')),
  offered_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (ride_id, driver_id)
);
create index if not exists ride_dispatch_attempts_ride_status_idx
  on public.ride_dispatch_attempts(ride_id, status);
create index if not exists ride_dispatch_attempts_driver_created_idx
  on public.ride_dispatch_attempts(driver_id, offered_at desc);

alter table public.ride_dispatch_attempts enable row level security;
revoke all on public.ride_dispatch_attempts from anon, authenticated;
grant select on public.ride_dispatch_attempts to authenticated;
drop policy if exists ride_dispatch_attempts_admin_read on public.ride_dispatch_attempts;
create policy ride_dispatch_attempts_admin_read on public.ride_dispatch_attempts
for select to authenticated using (public.has_app_role('admin'));

create or replace function public.driver_update_location(
  p_area_id uuid,
  p_latitude double precision,
  p_longitude double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_profile public.driver_profiles%rowtype;
begin
  if v_user is null or not public.has_app_role('driver') then
    raise exception 'driver_role_required' using errcode = '42501';
  end if;
  if p_latitude is null or p_longitude is null
     or p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;

  select * into v_profile
  from public.driver_profiles
  where user_id = v_user
  for update;
  if not found then raise exception 'driver_profile_missing' using errcode = 'P0002'; end if;
  if v_profile.status not in ('available','on_trip') then
    raise exception 'driver_not_online' using errcode = '42501';
  end if;
  if v_profile.current_area_id is distinct from p_area_id then
    raise exception 'driver_area_mismatch' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.service_areas a
    join public.area_business_settings s on s.area_id = a.id
    where a.id = p_area_id and a.active and s.active and s.service = 'ride'
      and s.business_model <> 'disabled'
  ) then
    raise exception 'service_unavailable' using errcode = '22023';
  end if;

  update public.driver_profiles
  set current_latitude = p_latitude,
      current_longitude = p_longitude,
      last_location_at = now()
  where user_id = v_user
  returning * into v_profile;

  return jsonb_build_object(
    'updated', true,
    'area_id', v_profile.current_area_id,
    'last_location_at', v_profile.last_location_at
  );
end;
$function$;
revoke all on function public.driver_update_location(uuid,double precision,double precision) from public, anon;
grant execute on function public.driver_update_location(uuid,double precision,double precision) to authenticated;

create or replace function public.driver_set_availability(p_area_id uuid, p_available boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_model text;
  v_profile public.driver_profiles%rowtype;
begin
  if v_user is null or not public.has_app_role('driver') then
    raise exception 'driver_role_required' using errcode = '42501';
  end if;
  select * into v_profile from public.driver_profiles where user_id = v_user for update;
  if not found then raise exception 'driver_profile_missing' using errcode = 'P0002'; end if;

  if p_available then
    if v_profile.status = 'on_trip' then
      raise exception 'active_ride_in_progress' using errcode = '22023';
    end if;
    select s.business_model into v_model
    from public.area_business_settings s
    join public.service_areas a on a.id = s.area_id
    where s.area_id = p_area_id and s.service = 'ride' and s.active and a.active;
    if not found or v_model = 'disabled' then
      raise exception 'service_unavailable' using errcode = '22023';
    end if;
    if v_model = 'subscription' and not exists (
      select 1 from public.driver_subscriptions d
      where d.driver_id = v_user and d.area_id = p_area_id and d.status = 'active'
        and d.starts_at <= now() and d.expires_at > now()
    ) then
      raise exception 'active_subscription_required' using errcode = '42501';
    end if;
    update public.driver_profiles
    set status = 'available', current_area_id = p_area_id
    where user_id = v_user
    returning * into v_profile;
  else
    if v_profile.status = 'on_trip' and exists (
      select 1 from public.rides r
      where r.driver_id = v_user and r.status in ('driver_assigned','driver_arriving','driver_arrived','in_trip')
    ) then
      raise exception 'active_ride_cannot_go_offline' using errcode = '22023';
    end if;
    update public.driver_profiles
    set status = 'offline', current_area_id = null
    where user_id = v_user
    returning * into v_profile;
  end if;

  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (v_user, 'driver_partner',
    case when p_available then 'driver.availability_on' else 'driver.availability_off' end,
    'driver_profile', v_user::text, 'success', jsonb_build_object('area_id', p_area_id));
  return to_jsonb(v_profile);
end;
$function$;
revoke all on function public.driver_set_availability(uuid,boolean) from public, anon;
grant execute on function public.driver_set_availability(uuid,boolean) to authenticated;

create or replace function public.auto_dispatch_ride(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_ride public.rides%rowtype;
  v_model text;
  v_auto_dispatch boolean;
  v_radius numeric;
  v_driver_id uuid;
  v_distance double precision;
begin
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  if v_ride.status <> 'searching' or v_ride.driver_id is not null then
    return jsonb_build_object('status', 'already_processed', 'ride_id', p_ride_id);
  end if;

  select s.business_model, s.auto_dispatch_enabled, s.dispatch_radius_km
  into v_model, v_auto_dispatch, v_radius
  from public.area_business_settings s
  join public.service_areas a on a.id = s.area_id
  where s.area_id = v_ride.service_area_id and s.service = 'ride' and s.active and a.active;
  if not found or v_model = 'disabled' then
    return jsonb_build_object('status', 'service_unavailable', 'ride_id', p_ride_id);
  end if;
  if not v_auto_dispatch then
    return jsonb_build_object('status', 'manual_dispatch', 'ride_id', p_ride_id);
  end if;

  select dp.user_id,
    (6371.0 * acos(least(1.0, greatest(-1.0,
      cos(radians(v_ride.pickup_lat)) * cos(radians(dp.current_latitude)) *
      cos(radians(dp.current_longitude) - radians(v_ride.pickup_lng)) +
      sin(radians(v_ride.pickup_lat)) * sin(radians(dp.current_latitude))
    )))) as distance_km
  into v_driver_id, v_distance
  from public.driver_profiles dp
  where dp.status = 'available'
    and dp.current_area_id = v_ride.service_area_id
    and dp.current_latitude is not null and dp.current_longitude is not null
    and dp.last_location_at >= now() - interval '2 minutes'
    and exists (
      select 1 from public.vehicles v
      where v.driver_id = dp.user_id and v.active and v.category = v_ride.category
    )
    and (
      v_model <> 'subscription'
      or exists (
        select 1 from public.driver_subscriptions d
        where d.driver_id = dp.user_id and d.area_id = v_ride.service_area_id
          and d.status = 'active' and d.starts_at <= now() and d.expires_at > now()
      )
    )
    and not exists (
      select 1 from public.ride_dispatch_attempts da
      where da.ride_id = v_ride.id and da.driver_id = dp.user_id
    )
  order by distance_km asc, dp.rating desc, dp.created_at asc
  limit 1
  for update of dp skip locked;

  if v_driver_id is null or v_distance > v_radius then
    insert into public.audit_events(actor_type, action, entity_type, entity_id, outcome, metadata)
    values ('system', 'ride.auto_dispatch_no_driver', 'ride', p_ride_id::text, 'failed',
      jsonb_build_object('area_id', v_ride.service_area_id, 'radius_km', v_radius, 'reason', 'no_eligible_driver_with_fresh_location'));
    return jsonb_build_object('status', 'no_driver', 'ride_id', p_ride_id);
  end if;

  update public.driver_profiles
  set status = 'on_trip', current_area_id = v_ride.service_area_id
  where user_id = v_driver_id and status = 'available';
  if not found then
    return jsonb_build_object('status', 'driver_race_lost', 'ride_id', p_ride_id);
  end if;

  update public.rides
  set driver_id = v_driver_id, status = 'driver_assigned', updated_at = now()
  where id = p_ride_id and status = 'searching' and driver_id is null
  returning * into v_ride;
  if not found then
    update public.driver_profiles set status = 'available' where user_id = v_driver_id and status = 'on_trip';
    return jsonb_build_object('status', 'ride_race_lost', 'ride_id', p_ride_id);
  end if;

  insert into public.ride_dispatch_attempts(ride_id, driver_id, status)
  values (p_ride_id, v_driver_id, 'offered')
  on conflict (ride_id, driver_id) do update
    set status = 'offered', offered_at = now(), resolved_at = null;

  insert into public.audit_events(actor_type, action, entity_type, entity_id, outcome, metadata)
  values ('system', 'ride.auto_dispatched', 'ride', p_ride_id::text, 'success',
    jsonb_build_object('driver_id', v_driver_id, 'area_id', v_ride.service_area_id, 'distance_km', round(v_distance::numeric, 2)));
  return jsonb_build_object('status', 'assigned', 'ride_id', p_ride_id, 'driver_id', v_driver_id, 'distance_km', round(v_distance::numeric, 2));
end;
$function$;
revoke all on function public.auto_dispatch_ride(uuid) from public, anon, authenticated;
grant execute on function public.auto_dispatch_ride(uuid) to service_role;

create or replace function public.auto_dispatch_new_ride_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $trigger$
begin
  if new.status = 'searching' and new.driver_id is null then
    begin
      perform public.auto_dispatch_ride(new.id);
    exception when others then
      insert into public.audit_events(actor_type, action, entity_type, entity_id, outcome, metadata)
      values ('system', 'ride.auto_dispatch_error', 'ride', new.id::text, 'failed',
        jsonb_build_object('sqlstate', sqlstate, 'error_code', case when sqlerrm in ('service_unavailable','no_eligible_driver') then sqlerrm else 'auto_dispatch_failed' end));
    end;
  end if;
  return new;
end;
$trigger$;
revoke all on function public.auto_dispatch_new_ride_trigger() from public, anon, authenticated;
drop trigger if exists rides_auto_dispatch_after_insert on public.rides;
create trigger rides_auto_dispatch_after_insert
after insert on public.rides
for each row execute function public.auto_dispatch_new_ride_trigger();

create or replace function public.driver_decline_ride(p_ride_id uuid, p_reason text default 'driver_declined')
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_ride public.rides%rowtype;
  v_dispatch jsonb;
begin
  if v_user is null or not public.has_app_role('driver') then
    raise exception 'driver_role_required' using errcode = '42501';
  end if;
  select * into v_ride from public.rides
  where id = p_ride_id and driver_id = v_user and status = 'driver_assigned'
  for update;
  if not found then raise exception 'ride_not_declinable' using errcode = '22023'; end if;

  update public.ride_dispatch_attempts
  set status = 'declined', resolved_at = now()
  where ride_id = p_ride_id and driver_id = v_user;

  update public.driver_profiles
  set status = 'available', current_area_id = v_ride.service_area_id
  where user_id = v_user and status = 'on_trip';

  update public.rides
  set driver_id = null, status = 'searching', updated_at = now()
  where id = p_ride_id;

  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (v_user, 'driver_partner', 'ride.driver_declined', 'ride', p_ride_id::text, 'success',
    jsonb_build_object('reason', left(coalesce(p_reason, 'driver_declined'), 120)));

  v_dispatch := public.auto_dispatch_ride(p_ride_id);
  select * into v_ride from public.rides where id = p_ride_id;
  return jsonb_build_object('ride', to_jsonb(v_ride), 'dispatch', v_dispatch);
end;
$function$;
revoke all on function public.driver_decline_ride(uuid,text) from public, anon;
grant execute on function public.driver_decline_ride(uuid,text) to authenticated;

create or replace function public.admin_assign_driver_to_ride(p_ride_id uuid, p_driver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_ride public.rides%rowtype;
  v_driver public.driver_profiles%rowtype;
begin
  if auth.uid() is null or not public.has_app_role('admin') then
    raise exception 'admin_role_required' using errcode = '42501';
  end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  if v_ride.status <> 'searching' then raise exception 'ride_not_searching' using errcode = '22023'; end if;
  select * into v_driver from public.driver_profiles where user_id = p_driver_id for update;
  if not found or v_driver.status <> 'available' then raise exception 'driver_not_available' using errcode = '22023'; end if;
  if not exists (
    select 1 from public.vehicles v
    where v.driver_id = p_driver_id and v.active and v.category = v_ride.category
  ) then raise exception 'driver_vehicle_category_mismatch' using errcode = '22023'; end if;
  if v_ride.business_model_snapshot = 'subscription' and not exists (
    select 1 from public.driver_subscriptions s where s.driver_id = p_driver_id
      and s.area_id = v_ride.service_area_id and s.status = 'active'
      and s.starts_at <= now() and s.expires_at > now()
  ) then raise exception 'active_subscription_required' using errcode = '42501'; end if;

  update public.driver_profiles set status = 'on_trip', current_area_id = v_ride.service_area_id
  where user_id = p_driver_id;
  update public.rides set driver_id = p_driver_id, status = 'driver_assigned', updated_at = now()
  where id = p_ride_id returning * into v_ride;

  insert into public.ride_dispatch_attempts(ride_id, driver_id, status)
  values (p_ride_id, p_driver_id, 'offered')
  on conflict (ride_id, driver_id) do update set status = 'offered', offered_at = now(), resolved_at = null;

  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (auth.uid(), 'admin', 'ride.driver_assigned', 'ride', v_ride.id::text, 'success',
    jsonb_build_object('driver_id', p_driver_id, 'service_area_id', v_ride.service_area_id));
  return to_jsonb(v_ride);
end;
$function$;
revoke all on function public.admin_assign_driver_to_ride(uuid,uuid) from public, anon;
grant execute on function public.admin_assign_driver_to_ride(uuid,uuid) to authenticated;

create or replace function public.driver_update_ride_status(p_ride_id uuid, p_new_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_ride public.rides%rowtype;
  v_allowed boolean := false;
  v_model text;
  v_can_stay_online boolean := false;
begin
  if auth.uid() is null or not public.has_app_role('driver') then
    raise exception 'driver_role_required' using errcode = '42501';
  end if;
  select * into v_ride from public.rides where id = p_ride_id and driver_id = auth.uid() for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  v_allowed := (v_ride.status = 'driver_assigned' and p_new_status = 'driver_arriving')
    or (v_ride.status = 'driver_arriving' and p_new_status = 'driver_arrived')
    or (v_ride.status = 'driver_arrived' and p_new_status = 'in_trip')
    or (v_ride.status = 'in_trip' and p_new_status = 'completed');
  if not v_allowed then raise exception 'invalid_ride_status_transition' using errcode = '22023'; end if;

  update public.rides set
    status = p_new_status,
    completed_at = case when p_new_status = 'completed' then now() else completed_at end,
    updated_at = now()
  where id = p_ride_id returning * into v_ride;

  if p_new_status = 'driver_arriving' then
    update public.ride_dispatch_attempts set status = 'accepted', resolved_at = now()
    where ride_id = p_ride_id and driver_id = auth.uid() and status = 'offered';
  end if;

  if p_new_status = 'in_trip' then
    update public.driver_profiles set status = 'on_trip' where user_id = auth.uid();
  elsif p_new_status = 'completed' then
    select s.business_model into v_model
    from public.area_business_settings s
    join public.service_areas a on a.id = s.area_id
    where s.area_id = v_ride.service_area_id and s.service = 'ride' and s.active and a.active;
    v_can_stay_online := found and v_model <> 'disabled' and (
      v_model <> 'subscription' or exists (
        select 1 from public.driver_subscriptions d
        where d.driver_id = auth.uid() and d.area_id = v_ride.service_area_id
          and d.status = 'active' and d.starts_at <= now() and d.expires_at > now()
      )
    );
    update public.driver_profiles
    set status = case when v_can_stay_online then 'available' else 'offline' end,
        current_area_id = case when v_can_stay_online then v_ride.service_area_id else null end
    where user_id = auth.uid();
  end if;

  insert into public.audit_events(actor_id, actor_type, action, entity_type, entity_id, outcome, metadata)
  values (auth.uid(), 'driver_partner', 'ride.status_updated', 'ride', v_ride.id::text, 'success',
    jsonb_build_object('status', p_new_status));
  return to_jsonb(v_ride);
end;
$function$;
revoke all on function public.driver_update_ride_status(uuid,text) from public, anon;
grant execute on function public.driver_update_ride_status(uuid,text) to authenticated;

create or replace function public.cancel_ride(
  p_ride_id uuid,
  p_idempotency_key uuid,
  p_reason text default 'customer_request'
)
returns public.rides
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_ride public.rides%rowtype;
  v_model text;
  v_can_stay_online boolean := false;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  if p_idempotency_key is null then raise exception 'invalid_request' using errcode = '22023'; end if;
  select * into v_ride from public.rides where id = p_ride_id and customer_id = v_user for update;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  if v_ride.status = 'cancelled' then return v_ride; end if;
  if v_ride.status not in ('searching','driver_assigned','driver_arriving','driver_arrived') then
    raise exception 'ride_not_cancellable' using errcode = '22023';
  end if;

  update public.rides set status = 'cancelled',
    cancellation_reason = left(coalesce(p_reason,'customer_request'),120),
    cancelled_at = now(), updated_at = now()
  where id = p_ride_id returning * into v_ride;

  if v_ride.driver_id is not null then
    update public.ride_dispatch_attempts set status = 'cancelled', resolved_at = now()
    where ride_id = p_ride_id and driver_id = v_ride.driver_id and status in ('offered','accepted');
    select s.business_model into v_model
    from public.area_business_settings s
    join public.service_areas a on a.id = s.area_id
    where s.area_id = v_ride.service_area_id and s.service = 'ride' and s.active and a.active;
    v_can_stay_online := found and v_model <> 'disabled' and (
      v_model <> 'subscription' or exists (
        select 1 from public.driver_subscriptions d
        where d.driver_id = v_ride.driver_id and d.area_id = v_ride.service_area_id
          and d.status = 'active' and d.starts_at <= now() and d.expires_at > now()
      )
    );
    update public.driver_profiles
    set status = case when v_can_stay_online then 'available' else 'offline' end,
        current_area_id = case when v_can_stay_online then v_ride.service_area_id else null end
    where user_id = v_ride.driver_id and status = 'on_trip';
  end if;
  return v_ride;
end;
$function$;
revoke all on function public.cancel_ride(uuid,uuid,text) from public, anon;
grant execute on function public.cancel_ride(uuid,uuid,text) to authenticated;

create or replace function public.get_ride_tracking(p_ride_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $function$
declare
  v_user uuid := auth.uid();
  v_ride public.rides%rowtype;
  v_driver public.driver_profiles%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  select * into v_ride from public.rides where id = p_ride_id;
  if not found then raise exception 'ride_not_found' using errcode = 'P0002'; end if;
  if v_ride.customer_id <> v_user and v_ride.driver_id is distinct from v_user and not public.has_app_role('admin') then
    raise exception 'ride_access_denied' using errcode = '42501';
  end if;
  if v_ride.driver_id is null then
    return jsonb_build_object('ride_id', v_ride.id, 'status', v_ride.status, 'driver', null);
  end if;
  select * into v_driver from public.driver_profiles where user_id = v_ride.driver_id;
  return jsonb_build_object(
    'ride_id', v_ride.id,
    'status', v_ride.status,
    'driver', jsonb_build_object(
      'name', v_driver.display_name,
      'rating', v_driver.rating,
      'latitude', v_driver.current_latitude,
      'longitude', v_driver.current_longitude,
      'location_updated_at', v_driver.last_location_at
    )
  );
end;
$function$;
revoke all on function public.get_ride_tracking(uuid) from public, anon;
grant execute on function public.get_ride_tracking(uuid) to authenticated;
