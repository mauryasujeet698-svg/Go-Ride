-- Maintain a monotonic ride sequence and append a durable event for each change.
create or replace function public.bump_ride_sequence()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.status is distinct from old.status or new.driver_id is distinct from old.driver_id then
    new.seq := old.seq + 1;
  else
    new.seq := old.seq;
  end if;
  return new;
end;
$$;

create or replace function public.record_ride_event()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    insert into public.ride_events(ride_id, seq, status, payload)
    values (new.id, new.seq, new.status, jsonb_build_object('driver_id', new.driver_id, 'fare_minor', new.fare_minor));
  elsif new.status is distinct from old.status or new.driver_id is distinct from old.driver_id then
    insert into public.ride_events(ride_id, seq, status, payload)
    values (new.id, new.seq, new.status, jsonb_build_object('driver_id', new.driver_id, 'fare_minor', new.fare_minor));
  end if;
  return new;
end;
$$;

drop trigger if exists rides_bump_sequence on public.rides;
create trigger rides_bump_sequence before update on public.rides
for each row execute function public.bump_ride_sequence();
drop trigger if exists rides_record_event on public.rides;
create trigger rides_record_event after insert or update on public.rides
for each row execute function public.record_ride_event();

revoke all on function public.record_ride_event() from public, anon, authenticated;
revoke all on function public.bump_ride_sequence() from public, anon, authenticated;
