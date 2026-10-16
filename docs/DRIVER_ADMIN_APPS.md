# Go-Ride Driver and Admin Apps

These are separate Flutter applications in the Go-Ride repository:

- `apps/driver_partner`: phone OTP sign-in and a driver application form.
- `apps/admin`: phone OTP sign-in and an explicit active-admin-role check.

## Build

Run each app from its own directory and pass only the public Supabase URL and anon/publishable key:

```sh
cd apps/driver_partner
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
```

Repeat with `apps/admin`.

Do not add the Supabase service-role key to a Flutter app, GitHub source, or a public build. Configure phone authentication and an SMS provider in Supabase Auth before testing OTP.

## Current backend scope

The Supabase migration adds:
- `user_roles`: server-managed roles; signed-in users can read their own roles but cannot grant/revoke roles.
- `driver_applications`: authenticated users can submit one application and read only their own application. Review fields cannot be updated directly by the client.

Admin approval/rejection and role grants must be performed by a trusted server-side function with authorization and audit logging. Do not approve drivers by directly changing client-controlled fields. The apps currently do not provide driver document upload, live location, dispatch, trip lifecycle, earnings, payment reconciliation, or operational admin actions.

The migration is in `supabase/migrations` for the current Go-Ride Supabase project. The separate `backend/migrations` directory belongs to the optional Fastify backend schema and should not be applied to the existing Supabase project without a deliberate schema reconciliation.
