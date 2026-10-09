# Go-Ride shared backend

This directory establishes the initial TypeScript API workspace, PostgreSQL/PostGIS schema, server-side feature configuration and ride lifecycle rules.

## Current status

**Foundation only; not production-ready.** This is not yet the complete booking backend. Authentication, authorization, live provider adapters, durable ride/quote endpoints, dispatch, realtime delivery, support workflows and payment endpoints must be implemented and tested before real customer use.

The API intentionally exposes only liveness/readiness and safe feature capability hints at this stage. It does not fabricate routes, fares, bookings, driver assignments or payments.

## Local setup

- Node.js 22+
- PostgreSQL with PostGIS enabled
- A private environment/secret manager for deployment secrets

Copy .env.example to .env using local-only credentials, create a local database, enable PostGIS, apply migrations/001_initial.sql, run npm install, then npm run typecheck and npm test after compilation.

The migration uses CREATE EXTENSION postgis; the database role must have permission to install it or an administrator must enable it first. Never use production credentials locally.

## Feature availability

All capabilities default to disabled. GET /v1/capabilities exposes presentation-safe flags only. This is not authorization. Every action endpoint must enforce feature availability and role/ownership server-side.

Payment mode live must not be used until a real provider adapter, webhook verification, reconciliation/refund logic, secret management, monitoring and operational approval exist. No gateway is selected or activated in this foundation.

## Security limitations

The API has no public ride mutation endpoints yet. It is not safe to expose as a production service until authentication, authorization, rate limiting, request validation and operational controls are implemented. DATABASE_SSL=true enables TLS with certificate verification. CORS is deny-by-default unless explicit origins are configured. Review all future logging for PII and precise location data.
