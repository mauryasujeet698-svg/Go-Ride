-- A shared, concurrency-safe AI usage budget. Cost is an estimate configured by Admin,
-- not a replacement for provider billing data.
alter table public.ai_runtime_settings
  add column if not exists estimated_cost_minor_per_request integer not null default 10
  check (estimated_cost_minor_per_request between 0 and 1000000);

create table if not exists public.ai_usage_events (
  id uuid primary key default gen_random_uuid(),
  job_type text not null check (job_type in ('daily_report','support_triage','security_audit','demand_analysis')),
  provider text not null check (provider in ('openai','gemini','anthropic')),
  model text not null check (char_length(model) between 1 and 120),
  status text not null default 'reserved' check (status in ('reserved','succeeded','failed')),
  estimated_cost_minor integer not null check (estimated_cost_minor >= 0),
  input_tokens integer check (input_tokens is null or input_tokens >= 0),
  output_tokens integer check (output_tokens is null or output_tokens >= 0),
  request_id text,
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists ai_usage_events_created_idx on public.ai_usage_events(created_at desc);
create index if not exists ai_usage_events_job_created_idx on public.ai_usage_events(job_type, created_at desc);

alter table public.ai_usage_events enable row level security;
drop policy if exists ai_usage_events_admin_read on public.ai_usage_events;
create policy ai_usage_events_admin_read on public.ai_usage_events
for select to authenticated using (public.has_app_role('admin'));
revoke all privileges on public.ai_usage_events from anon, authenticated;
grant select on public.ai_usage_events to authenticated;

create or replace function public.reserve_ai_usage_budget(
  p_job_type text,
  p_provider text,
  p_model text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $budget$
declare
  v_settings public.ai_runtime_settings%rowtype;
  v_requests bigint;
  v_cost bigint;
  v_usage_id uuid;
begin
  if p_job_type not in ('daily_report','support_triage','security_audit','demand_analysis')
     or p_provider not in ('openai','gemini','anthropic')
     or p_model is null or char_length(p_model) < 1 or char_length(p_model) > 120 then
    raise exception 'invalid_ai_budget_request' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('go-ride-ai-budget-24h', 0));
  select * into v_settings from public.ai_runtime_settings where singleton = true;
  if not found or not v_settings.enabled then
    raise exception 'ai_disabled' using errcode = 'P0001';
  end if;

  select count(*), coalesce(sum(estimated_cost_minor), 0)
    into v_requests, v_cost
  from public.ai_usage_events
  where created_at >= now() - interval '24 hours';

  if v_requests >= v_settings.max_requests_per_day then
    raise exception 'ai_request_budget_exceeded' using errcode = 'P0001';
  end if;
  if v_cost + v_settings.estimated_cost_minor_per_request > v_settings.max_cost_minor_per_day then
    raise exception 'ai_cost_budget_exceeded' using errcode = 'P0001';
  end if;

  insert into public.ai_usage_events(job_type, provider, model, status, estimated_cost_minor)
  values (p_job_type, p_provider, p_model, 'reserved', v_settings.estimated_cost_minor_per_request)
  returning id into v_usage_id;
  return v_usage_id;
end;
$budget$;
revoke all on function public.reserve_ai_usage_budget(text,text,text) from public, anon, authenticated;
grant execute on function public.reserve_ai_usage_budget(text,text,text) to service_role;
