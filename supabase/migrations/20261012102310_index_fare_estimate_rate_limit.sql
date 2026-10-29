-- Index used by the server-side fare-estimate rate limiter.
create index if not exists ride_quotes_customer_created_idx
  on public.ride_quotes(customer_id, created_at desc);
