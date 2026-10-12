create or replace function public.estimate_fares_from_route(
  p_customer_id uuid, p_pickup_lat double precision, p_pickup_lng double precision,
  p_destination_lat double precision, p_destination_lng double precision,
  p_distance_km double precision, p_eta_seconds integer
)
returns table(quote_id uuid, category text, amount_minor integer, currency character, eta_seconds integer, expires_at timestamptz)
language plpgsql security definer set search_path = public, auth, pg_temp
as $function$
declare r record; v_distance_km double precision; v_recent_quotes bigint; v_fare integer;
begin
  if p_customer_id is null or not exists(select 1 from auth.users u where u.id=p_customer_id) then raise exception 'invalid_customer' using errcode='22023'; end if;
  if p_pickup_lat is null or p_pickup_lat not between -90 and 90 or p_destination_lat is null or p_destination_lat not between -90 and 90
    or p_pickup_lng is null or p_pickup_lng not between -180 and 180 or p_destination_lng is null or p_destination_lng not between -180 and 180
    or p_distance_km is null or p_distance_km < 0 or p_distance_km > 200 or p_eta_seconds is null or p_eta_seconds < 1 or p_eta_seconds > 86400
    then raise exception 'invalid_estimate_request' using errcode='22023'; end if;
  v_distance_km := 6371 * 2 * asin(sqrt(power(sin(radians(p_destination_lat-p_pickup_lat)/2),2)
    + cos(radians(p_pickup_lat))*cos(radians(p_destination_lat))*power(sin(radians(p_destination_lng-p_pickup_lng)/2),2)));
  if p_distance_km + 0.25 < v_distance_km then raise exception 'route_distance_invalid' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text,0));
  select count(*) into v_recent_quotes from public.ride_quotes where customer_id=p_customer_id and created_at>now()-interval '1 minute';
  if v_recent_quotes >= 60 then raise exception 'rate_limited' using errcode='P0001'; end if;
  for r in select pr.* from public.pricing_rules pr where pr.enabled order by pr.category loop
    v_fare := greatest(r.minimum_fare_minor,r.base_fare_minor+ceil(p_distance_km*r.per_km_minor)::integer);
    quote_id:=gen_random_uuid(); category:=r.category; amount_minor:=v_fare; currency:=r.currency; eta_seconds:=p_eta_seconds; expires_at:=now()+interval '2 minutes';
    insert into public.ride_quotes(id,customer_id,pickup_lat,pickup_lng,destination_lat,destination_lng,category,fare_minor,currency,eta_seconds,expires_at)
    values(quote_id,p_customer_id,p_pickup_lat,p_pickup_lng,p_destination_lat,p_destination_lng,category,amount_minor,currency,eta_seconds,expires_at);
    return next;
  end loop;
end;
$function$;
revoke all on function public.estimate_fares_from_route(uuid,double precision,double precision,double precision,double precision,double precision,integer) from public, anon, authenticated;
grant execute on function public.estimate_fares_from_route(uuid,double precision,double precision,double precision,double precision,double precision,integer) to service_role;