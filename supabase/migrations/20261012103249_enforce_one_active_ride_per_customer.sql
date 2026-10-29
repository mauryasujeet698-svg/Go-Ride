-- Prevent a customer from holding multiple simultaneous active rides.
create unique index if not exists rides_one_active_per_customer
  on public.rides(customer_id)
  where status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip');
