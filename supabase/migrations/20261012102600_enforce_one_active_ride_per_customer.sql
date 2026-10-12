-- Prevent two concurrent booking requests from leaving a customer with
-- multiple active rides. The unique index is the final concurrency guard.
create unique index if not exists rides_one_active_per_customer_uidx
on public.rides(customer_id)
where status in ('searching','driver_assigned','driver_arriving','driver_arrived','otp_required','in_trip');
