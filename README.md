# Go-Ride

Production-oriented ride-hailing customer application foundation.

## Current status

- Batch 1: domain foundation — frozen
- Batch 2: application synchronization + RideBloc — frozen
- Batch 3: infrastructure — not started

## Architecture principles

REST snapshots are authoritative. Realtime is a transport layer and is reconciled against the authoritative ride version.

The project is intentionally structured so HTTP, realtime, authentication, maps, routing and persistence implementations can be added behind interfaces without leaking vendor types into the domain.

## Development

This repository currently contains the frozen Batch 1/2 contracts and tests. Generated Freezed files are intentionally not committed.

Run:

`flutter pub get`

`dart run build_runner build --delete-conflicting-outputs`

`flutter analyze`

`flutter test`

Do not add secrets, API keys, credentials or signing material to this public repository.

Batch 3 must not be started until the current repository has passed independent architecture/security review.
