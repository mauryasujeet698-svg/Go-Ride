create or replace function public.get_ai_daily_metrics(
  p_period_start timestamptz,
  p_period_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if p_period_start is null or p_period_end is null or p_period_end <= p_period_start then
    raise exception 'invalid_reporting_period' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'period', jsonb_build_object('start', p_period_start, 'end', p_period_end),
    'rides', (
      select jsonb_build_object(
        'created', count(*),
        'completed', count(*) filter (where status = 'completed'),
        'cancelled', count(*) filter (where status = 'cancelled'),
        'failed', count(*) filter (where status = 'failed'),
        'active_at_query_time', count(*) filter (where status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip'))
      )
      from public.rides
      where created_at >= p_period_start and created_at < p_period_end
    ),
    'demand_by_area', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'area_code', coalesce(a.code, 'UNASSIGNED'),
        'area_name', coalesce(a.name, 'Unassigned'),
        'requests', d.requests,
        'completed', d.completed,
        'cancelled', d.cancelled,
        'searching_now', d.searching_now,
        'average_fare_minor', d.average_fare_minor
      ) order by d.requests desc, coalesce(a.code, 'UNASSIGNED')), '[]'::jsonb)
      from (
        select service_area_id,
          count(*) as requests,
          count(*) filter (where status = 'completed') as completed,
          count(*) filter (where status = 'cancelled') as cancelled,
          count(*) filter (where status = 'searching') as searching_now,
          round(avg(fare_minor))::bigint as average_fare_minor
        from public.rides
        where created_at >= p_period_start and created_at < p_period_end
        group by service_area_id
      ) d
      left join public.service_areas a on a.id = d.service_area_id
    ),
    'demand_by_category', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'category', category,
        'requests', requests,
        'completed', completed,
        'cancelled', cancelled
      ) order by requests desc, category), '[]'::jsonb)
      from (
        select category, count(*) as requests,
          count(*) filter (where status = 'completed') as completed,
          count(*) filter (where status = 'cancelled') as cancelled
        from public.rides
        where created_at >= p_period_start and created_at < p_period_end
        group by category
      ) c
    ),
    'demand_by_hour', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'hour_utc', hour_utc,
        'requests', requests,
        'completed', completed
      ) order by hour_utc), '[]'::jsonb)
      from (
        select date_trunc('hour', created_at) as hour_utc,
          count(*) as requests,
          count(*) filter (where status = 'completed') as completed
        from public.rides
        where created_at >= p_period_start and created_at < p_period_end
        group by date_trunc('hour', created_at)
      ) h
    ),
    'quote_conversion', (
      select jsonb_build_object(
        'quotes_created', count(*),
        'quotes_used', count(*) filter (where used_at is not null),
        'conversion_percent', case when count(*) = 0 then 0
          else round(100.0 * count(*) filter (where used_at is not null) / count(*), 2) end
      )
      from public.ride_quotes
      where created_at >= p_period_start and created_at < p_period_end
    ),
    'driver_supply', (
      select jsonb_build_object(
        'total_profiles', count(*),
        'available', count(*) filter (where status = 'available'),
        'on_trip', count(*) filter (where status = 'on_trip'),
        'offline', count(*) filter (where status = 'offline'),
        'suspended', count(*) filter (where status = 'suspended')
      )
      from public.driver_profiles
    ),
    'financials', (
      select jsonb_build_object(
        'gross_fare_minor', coalesce(sum(fare_minor), 0),
        'commission_minor', coalesce(sum(commission_minor), 0),
        'driver_net_minor', coalesce(sum(driver_net_minor), 0),
        'currency', 'INR'
      )
      from public.ride_financials
      where created_at >= p_period_start and created_at < p_period_end
    ),
    'revenue_by_model', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'business_model', business_model_snapshot,
        'completed_rides', completed_rides,
        'gross_fare_minor', gross_fare_minor,
        'commission_minor', commission_minor,
        'driver_net_minor', driver_net_minor
      ) order by business_model_snapshot), '[]'::jsonb)
      from (
        select business_model_snapshot,
          count(*) as completed_rides,
          coalesce(sum(fare_minor), 0) as gross_fare_minor,
          coalesce(sum(commission_minor), 0) as commission_minor,
          coalesce(sum(driver_net_minor), 0) as driver_net_minor
        from public.ride_financials
        where created_at >= p_period_start and created_at < p_period_end
        group by business_model_snapshot
      ) f
    ),
    'subscriptions', (
      select jsonb_build_object(
        'created_in_period', count(*) filter (where created_at >= p_period_start and created_at < p_period_end),
        'active_now', count(*) filter (where status = 'active' and expires_at > now()),
        'expiring_in_24h', count(*) filter (where status = 'active' and expires_at > now() and expires_at <= now() + interval '24 hours'),
        'subscription_revenue_minor_in_period', coalesce(sum(price_minor_snapshot) filter (where created_at >= p_period_start and created_at < p_period_end), 0)
      )
      from public.driver_subscriptions
    ),
    'support', (
      select jsonb_build_object(
        'opened_in_period', count(*) filter (where created_at >= p_period_start and created_at < p_period_end),
        'unresolved', count(*) filter (where status not in ('resolved','closed')),
        'needs_human', count(*) filter (where needs_human and status not in ('resolved','closed')),
        'urgent_unresolved', count(*) filter (where priority = 'urgent' and status not in ('resolved','closed'))
      )
      from public.support_tickets
    ),
    'active_areas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'area_code', a.code,
        'area_name', a.name,
        'service', s.service,
        'business_model', s.business_model,
        'commission_bps', s.commission_bps
      ) order by a.code, s.service), '[]'::jsonb)
      from public.service_areas a
      left join public.area_business_settings s on s.area_id = a.id and s.active
      where a.active
    )
  );
end;
$function$;
revoke all on function public.get_ai_daily_metrics(timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function public.get_ai_daily_metrics(timestamptz,timestamptz) to service_role;
