-- Prevent concurrent requests from creating multiple active rides for one customer.
create unique index if not exists rides_one_active_per_customer_uidx
on public.rides(customer_id)
where status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip');
