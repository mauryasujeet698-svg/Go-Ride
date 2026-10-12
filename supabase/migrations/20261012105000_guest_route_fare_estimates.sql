create or replace function public.estimate_guest_fares(p_distance_km double precision, p_eta_seconds integer default 300)
returns table(category text, amount_minor integer, currency character, eta_seconds integer)
language plpgsql security definer set search_path = public, pg_temp
as $function$
declare r record;
begin
  if p_distance_km is null or p_distance_km < 0 or p_distance_km > 200
     or p_eta_seconds is null or p_eta_seconds < 1 or p_eta_seconds > 86400 then
    raise exception 'invalid_estimate_request' using errcode = '22023';
  end if;
  for r in select pr.category, pr.base_fare_minor, pr.per_km_minor, pr.minimum_fare_minor, pr.currency
    from public.pricing_rules pr where pr.enabled order by pr.category
  loop
    category := r.category;
    amount_minor := greatest(r.minimum_fare_minor, r.base_fare_minor + ceil(p_distance_km * r.per_km_minor)::integer);
    currency := r.currency;
    eta_seconds := p_eta_seconds;
    return next;
  end loop;
end;
$function$;
revoke all on function public.estimate_guest_fares(double precision, integer) from public;
grant execute on function public.estimate_guest_fares(double precision, integer) to anon, authenticated;