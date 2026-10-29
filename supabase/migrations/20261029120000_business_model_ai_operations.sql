-- Go-Ride configurable business models, subscription ledger and AI operations foundation.
-- Provider credentials MUST be stored as Supabase Edge Function secrets, never in these tables.

create table if not exists public.app_user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'support_agent', 'driver_partner')),
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

create or replace function public.has_app_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.app_user_roles r
    where r.user_id = auth.uid() and r.role = p_role
  );
$$;
revoke all on function public.has_app_role(text) from public, anon;
grant execute on function public.has_app_role(text) to authenticated;

create table if not exists public.service_areas (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (char_length(code) between 2 and 64),
  name text not null check (char_length(name) between 2 and 120),
  city text,
  district text,
  state text,
  pincode text check (pincode is null or pincode ~ '^[1-9][0-9]{5}$'),
  timezone text not null default 'Asia/Kolkata',
  active boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.service_areas(code, name, active)
values ('DEFAULT', 'Default service area', true)
on conflict (code) do nothing;

create table if not exists public.area_business_settings (
  id uuid primary key default gen_random_uuid(),
  area_id uuid not null references public.service_areas(id) on delete restrict,
  service text not null check (service in ('ride', 'parcel')),
  business_model text not null check (business_model in ('subscription', 'commission', 'disabled')),
  commission_bps integer not null default 0 check (commission_bps between 0 and 10000),
  active boolean not null default true,
  effective_from timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (area_id, service)
);

insert into public.area_business_settings(area_id, service, business_model, commission_bps, active)
select id, 'ride', 'subscription', 0, true
from public.service_areas where code = 'DEFAULT'
on conflict (area_id, service) do nothing;

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  area_id uuid not null references public.service_areas(id) on delete restrict,
  service text not null default 'ride' check (service = 'ride'),
  name text not null check (char_length(name) between 2 and 120),
  description text not null default '' check (char_length(description) <= 1000),
  price_minor bigint not null check (price_minor >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  duration_minutes integer not null default 1440 check (duration_minutes between 15 and 525600),
  active boolean not null default false,
  effective_from timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans(area_id, name, description, price_minor, currency, duration_minutes, active)
select id, '24-hour driver pass', 'Default plan; administrators can change the price, duration and availability.', 5000, 'INR', 1440, true
from public.service_areas where code = 'DEFAULT'
and not exists (
  select 1 from public.subscription_plans p where p.area_id = service_areas.id and p.name = '24-hour driver pass'
);

create table if not exists public.driver_subscriptions (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references auth.users(id) on delete restrict,
  area_id uuid not null references public.service_areas(id) on delete restrict,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,
  status text not null default 'pending_payment' check (status in ('pending_payment', 'active', 'expired', 'cancelled', 'refunded')),
  price_minor_snapshot bigint not null check (price_minor_snapshot >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  duration_minutes_snapshot integer not null check (duration_minutes_snapshot between 15 and 525600),
  starts_at timestamptz,
  expires_at timestamptz,
  idempotency_key text not null check (char_length(idempotency_key) between 16 and 128),
  payment_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (idempotency_key),
  check (expires_at is null or starts_at is null or expires_at > starts_at)
);
create index if not exists driver_subscriptions_driver_status_expiry_idx
  on public.driver_subscriptions(driver_id, status, expires_at desc);
create index if not exists driver_subscriptions_area_status_idx
  on public.driver_subscriptions(area_id, status, expires_at desc);

create table if not exists public.ride_financials (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null unique references public.rides(id) on delete restrict,
  area_id uuid not null references public.service_areas(id) on delete restrict,
  business_model_snapshot text not null check (business_model_snapshot in ('subscription', 'commission')),
  fare_minor bigint not null check (fare_minor >= 0),
  commission_bps_snapshot integer not null default 0 check (commission_bps_snapshot between 0 and 10000),
  commission_minor bigint not null default 0 check (commission_minor >= 0),
  driver_net_minor bigint not null check (driver_net_minor >= 0),
  currency char(3) not null default 'INR' check (currency = 'INR'),
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  check (commission_minor <= fare_minor),
  check (driver_net_minor = fare_minor - commission_minor),
  check (business_model_snapshot <> 'subscription' or commission_minor = 0)
);
create index if not exists ride_financials_area_created_idx
  on public.ride_financials(area_id, created_at desc);

create table if not exists public.ai_runtime_settings (
  singleton boolean primary key default true check (singleton),
  provider text not null default 'none' check (provider in ('none', 'openai', 'gemini', 'anthropic')),
  model text,
  enabled boolean not null default false,
  daily_report_enabled boolean not null default false,
  report_interval_hours integer not null default 24 check (report_interval_hours between 1 and 168),
  max_requests_per_day integer not null default 1000 check (max_requests_per_day between 1 and 1000000),
  max_cost_minor_per_day bigint not null default 100000 check (max_cost_minor_per_day >= 0),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.ai_runtime_settings(singleton, provider, enabled, daily_report_enabled, report_interval_hours)
values (true, 'none', false, false, 24)
on conflict (singleton) do nothing;

create table if not exists public.daily_ai_reports (
  id uuid primary key default gen_random_uuid(),
  period_start timestamptz not null,
  period_end timestamptz not null,
  timezone text not null default 'Asia/Kolkata',
  status text not null default 'pending' check (status in ('pending', 'running', 'succeeded', 'failed')),
  metrics jsonb not null default '{}'::jsonb,
  summary text not null default '',
  findings jsonb not null default '[]'::jsonb,
  recommendations jsonb not null default '[]'::jsonb,
  provider text not null default 'none' check (provider in ('none', 'openai', 'gemini', 'anthropic')),
  model text,
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (period_end > period_start),
  unique (period_start, period_end)
);
create index if not exists daily_ai_reports_created_idx on public.daily_ai_reports(created_at desc);

create table if not exists public.ai_job_runs (
  id uuid primary key default gen_random_uuid(),
  job_type text not null check (job_type in ('daily_report', 'support_triage', 'security_audit', 'demand_analysis')),
  status text not null default 'pending' check (status in ('pending', 'running', 'succeeded', 'failed', 'skipped')),
  started_at timestamptz,
  finished_at timestamptz,
  input_summary jsonb not null default '{}'::jsonb,
  output_summary jsonb not null default '{}'::jsonb,
  provider text not null default 'none' check (provider in ('none', 'openai', 'gemini', 'anthropic')),
  model text,
  error_code text,
  created_at timestamptz not null default now(),
  check (finished_at is null or started_at is null or finished_at >= started_at)
);
create index if not exists ai_job_runs_type_created_idx on public.ai_job_runs(job_type, created_at desc);

create table if not exists public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  actor_type text not null default 'system' check (actor_type in ('admin', 'customer', 'driver_partner', 'ai_agent', 'system', 'support_agent')),
  action text not null check (char_length(action) between 2 and 120),
  entity_type text not null check (char_length(entity_type) between 2 and 80),
  entity_id text,
  request_id text,
  outcome text not null default 'success' check (outcome in ('success', 'denied', 'failed', 'flagged')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_events_created_idx on public.audit_events(created_at desc);
create index if not exists audit_events_entity_idx on public.audit_events(entity_type, entity_id, created_at desc);

alter table public.support_tickets
  add column if not exists ai_attempt_count integer not null default 0 check (ai_attempt_count between 0 and 100),
  add column if not exists needs_human boolean not null default false,
  add column if not exists escalated_at timestamptz,
  add column if not exists priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  add column if not exists assigned_to uuid references auth.users(id) on delete set null,
  add column if not exists ai_summary text;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists service_areas_touch_updated_at on public.service_areas;
create trigger service_areas_touch_updated_at before update on public.service_areas
for each row execute function public.touch_updated_at();
drop trigger if exists area_business_settings_touch_updated_at on public.area_business_settings;
create trigger area_business_settings_touch_updated_at before update on public.area_business_settings
for each row execute function public.touch_updated_at();
drop trigger if exists subscription_plans_touch_updated_at on public.subscription_plans;
create trigger subscription_plans_touch_updated_at before update on public.subscription_plans
for each row execute function public.touch_updated_at();
drop trigger if exists driver_subscriptions_touch_updated_at on public.driver_subscriptions;
create trigger driver_subscriptions_touch_updated_at before update on public.driver_subscriptions
for each row execute function public.touch_updated_at();
drop trigger if exists ai_runtime_settings_touch_updated_at on public.ai_runtime_settings;
create trigger ai_runtime_settings_touch_updated_at before update on public.ai_runtime_settings
for each row execute function public.touch_updated_at();

alter table public.app_user_roles enable row level security;
alter table public.service_areas enable row level security;
alter table public.area_business_settings enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.driver_subscriptions enable row level security;
alter table public.ride_financials enable row level security;
alter table public.ai_runtime_settings enable row level security;
alter table public.daily_ai_reports enable row level security;
alter table public.ai_job_runs enable row level security;
alter table public.audit_events enable row level security;

drop policy if exists app_user_roles_select_self_or_admin on public.app_user_roles;
create policy app_user_roles_select_self_or_admin on public.app_user_roles
for select to authenticated using (user_id = (select auth.uid()) or public.has_app_role('admin'));

drop policy if exists service_areas_read_active on public.service_areas;
create policy service_areas_read_active on public.service_areas
for select to anon, authenticated using (active or public.has_app_role('admin'));
drop policy if exists service_areas_admin_manage on public.service_areas;
create policy service_areas_admin_manage on public.service_areas
for all to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));

drop policy if exists area_business_settings_read_active on public.area_business_settings;
create policy area_business_settings_read_active on public.area_business_settings
for select to anon, authenticated using (
  active and exists (select 1 from public.service_areas a where a.id = area_id and a.active)
  or public.has_app_role('admin')
);
drop policy if exists area_business_settings_admin_manage on public.area_business_settings;
create policy area_business_settings_admin_manage on public.area_business_settings
for all to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));

drop policy if exists subscription_plans_read_active on public.subscription_plans;
create policy subscription_plans_read_active on public.subscription_plans
for select to anon, authenticated using (
  active and exists (select 1 from public.service_areas a where a.id = area_id and a.active)
  or public.has_app_role('admin')
);
drop policy if exists subscription_plans_admin_manage on public.subscription_plans;
create policy subscription_plans_admin_manage on public.subscription_plans
for all to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));

drop policy if exists driver_subscriptions_read_own_or_admin on public.driver_subscriptions;
create policy driver_subscriptions_read_own_or_admin on public.driver_subscriptions
for select to authenticated using (driver_id = (select auth.uid()) or public.has_app_role('admin'));

drop policy if exists ride_financials_driver_or_admin_read on public.ride_financials;
create policy ride_financials_driver_or_admin_read on public.ride_financials
for select to authenticated using (
  public.has_app_role('admin') or exists (
    select 1 from public.rides r where r.id = ride_id and r.driver_id = (select auth.uid())
  )
);

drop policy if exists ai_runtime_settings_admin_read on public.ai_runtime_settings;
create policy ai_runtime_settings_admin_read on public.ai_runtime_settings
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists ai_runtime_settings_admin_update on public.ai_runtime_settings;
create policy ai_runtime_settings_admin_update on public.ai_runtime_settings
for update to authenticated using (public.has_app_role('admin')) with check (public.has_app_role('admin'));

drop policy if exists daily_ai_reports_admin_read on public.daily_ai_reports;
create policy daily_ai_reports_admin_read on public.daily_ai_reports
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists ai_job_runs_admin_read on public.ai_job_runs;
create policy ai_job_runs_admin_read on public.ai_job_runs
for select to authenticated using (public.has_app_role('admin'));
drop policy if exists audit_events_admin_read on public.audit_events;
create policy audit_events_admin_read on public.audit_events
for select to authenticated using (public.has_app_role('admin'));

drop policy if exists support_tickets_admin_read on public.support_tickets;
create policy support_tickets_admin_read on public.support_tickets
for select to authenticated using (public.has_app_role('admin') or user_id = (select auth.uid()));

revoke all privileges on public.app_user_roles from anon, authenticated;
revoke all privileges on public.service_areas from anon, authenticated;
revoke all privileges on public.area_business_settings from anon, authenticated;
revoke all privileges on public.subscription_plans from anon, authenticated;
revoke all privileges on public.driver_subscriptions from anon, authenticated;
revoke all privileges on public.ride_financials from anon, authenticated;
revoke all privileges on public.ai_runtime_settings from anon, authenticated;
revoke all privileges on public.daily_ai_reports from anon, authenticated;
revoke all privileges on public.ai_job_runs from anon, authenticated;
revoke all privileges on public.audit_events from anon, authenticated;

grant select on public.app_user_roles to authenticated;
grant select on public.service_areas to anon, authenticated;
grant insert, update, delete on public.service_areas to authenticated;
grant select on public.area_business_settings to anon, authenticated;
grant insert, update, delete on public.area_business_settings to authenticated;
grant select on public.subscription_plans to anon, authenticated;
grant insert, update, delete on public.subscription_plans to authenticated;
grant select on public.driver_subscriptions to authenticated;
grant select on public.ride_financials to authenticated;
grant select, update on public.ai_runtime_settings to authenticated;
grant select on public.daily_ai_reports to authenticated;
grant select on public.ai_job_runs to authenticated;
grant select on public.audit_events to authenticated;
