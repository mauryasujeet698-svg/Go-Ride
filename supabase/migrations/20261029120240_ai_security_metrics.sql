create or replace function public.get_ai_security_metrics(p_period_start timestamptz, p_period_end timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog, pg_temp
as $security$
begin
  if p_period_start is null or p_period_end is null or p_period_end <= p_period_start then
    raise exception 'invalid_reporting_period' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'period', jsonb_build_object('start', p_period_start, 'end', p_period_end),
    'public_tables_without_rls', (
      select coalesce(jsonb_agg(c.relname order by c.relname), '[]'::jsonb)
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
    ),
    'security_definer_functions_executable_by_anon', (
      select coalesce(jsonb_agg(jsonb_build_object('name', p.proname, 'arguments', pg_get_function_identity_arguments(p.oid)) order by p.proname), '[]'::jsonb)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prosecdef
        and has_function_privilege('anon', p.oid, 'EXECUTE')
        and p.prorettype <> 'trigger'::regtype
    ),
    'rides_searching_over_10_minutes', (
      select count(*) from public.rides where status = 'searching' and created_at < now() - interval '10 minutes'
    ),
    'active_subscriptions_past_expiry', (
      select count(*) from public.driver_subscriptions where status = 'active' and expires_at <= now()
    ),
    'urgent_unresolved_support_tickets', (
      select count(*) from public.support_tickets where priority = 'urgent' and status not in ('resolved','closed')
    ),
    'denied_or_failed_audit_events', (
      select count(*) from public.audit_events
      where created_at >= p_period_start and created_at < p_period_end and outcome in ('denied','failed','flagged')
    ),
    'failed_ai_jobs', (
      select count(*) from public.ai_job_runs
      where created_at >= p_period_start and created_at < p_period_end and status = 'failed'
    ),
    'configuration_changes', (
      select count(*) from public.audit_events
      where created_at >= p_period_start and created_at < p_period_end and action like 'config.%'
    ),
    'active_areas_without_coverage', (
      select count(*) from public.service_areas
      where active and code <> 'DEFAULT' and (center_lat is null or center_lng is null or coverage_radius_km <= 0)
    )
  );
end;
$security$;
revoke all on function public.get_ai_security_metrics(timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function public.get_ai_security_metrics(timestamptz,timestamptz) to service_role;
