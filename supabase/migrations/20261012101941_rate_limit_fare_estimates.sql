-- Server-side per-user rate limit for fare estimates.
create or replace function public.estimate_fares(
  p_pickup_lat double precision, p_pickup_lng double precision,
  p_destination_lat double precision, p_destination_lng double precision
)
returns table(quote_id uuid, category text, amount_minor integer, currency char(3), eta_seconds integer, expires_at timestamptz)
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_user uuid := auth.uid();
  v_distance_km double precision;
  v_recent_quotes bigint;
  r record;
  v_fare integer;
begin
  if v_user is null then raise exception 'authentication_required' using errcode = '28000'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 0));
  select count(*) into v_recent_quotes from public.ride_quotes
  where customer_id = v_user and created_at > now() - interval '1 minute';
  if v_recent_quotes >= 60 then raise exception 'rate_limited' using errcode = 'P0001'; end if;
  if p_pickup_lat not between -90 and 90 or p_destination_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180 or p_destination_lng not between -180 and 180 then
    raise exception 'invalid_coordinates' using errcode = '22023';
  end if;
  v_distance_km := 6371 * 2 * asin(sqrt(
    power(sin(radians(p_destination_lat - p_pickup_lat) / 2), 2) +
    cos(radians(p_pickup_lat)) * cos(radians(p_destination_lat)) *
    power(sin(radians(p_destination_lng - p_pickup_lng) / 2), 2)
  ));
  if v_distance_km > 200 then raise exception 'trip_too_long' using errcode = '22023'; end if;
  for r in select pr.* from public.pricing_rules pr where pr.enabled order by pr.category loop
    v_fare := greatest(r.minimum_fare_minor, r.base_fare_minor + ceil(v_distance_km * r.per_km_minor)::integer);
    quote_id := gen_random_uuid();
    category := r.category;
    amount_minor := v_fare;
    currency := r.currency;
    eta_seconds := 300;
    expires_at := now() + interval '2 minutes';
    insert into public.ride_quotes(id, customer_id, pickup_lat, pickup_lng, destination_lat, destination_lng, category, fare_minor, currency, eta_seconds, expires_at)
    values (quote_id, v_user, p_pickup_lat, p_pickup_lng, p_destination_lat, p_destination_lng, category, amount_minor, currency, eta_seconds, expires_at);
    return next;
  end loop;
end;
$$;
revoke all on function public.estimate_fares(double precision,double precision,double precision,double precision) from public, anon;
grant execute on function public.estimate_fares(double precision,double precision,double precision,double precision) to authenticated;
