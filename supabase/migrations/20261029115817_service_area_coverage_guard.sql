-- Prevent an enabled area from being activated without enforceable coverage.
alter table public.service_areas
  drop constraint if exists service_areas_active_area_coverage_check;
alter table public.service_areas
  add constraint service_areas_active_area_coverage_check
  check (
    not active
    or code = 'DEFAULT'
    or (
      center_lat is not null
      and center_lng is not null
      and coverage_radius_km > 0
    )
  );
