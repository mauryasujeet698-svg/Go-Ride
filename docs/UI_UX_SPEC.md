# Go-Ride UI/UX Specification

## Product boundary
Go-Ride v1 is ride-hailing only. No bus/train/flight/hotel, parcel delivery, restaurant delivery or general travel marketplace features. Customer and driver mobile apps are separate. Admin is recommended as a responsive web console because verification, support queues and audit timelines need dense operational layouts.

## Visual system
- Use Material 3 with stable Go-Ride design tokens rather than per-screen colors.
- Brand direction: deep navy structure, green primary action/accent, neutral off-white surfaces, semantic status colors. Pair status color with text/icon.
- Light and dark themes both require explicit text/surface contrast checks. Do not use low-opacity grey text for important labels in dark mode.
- Aim for 48 dp touch targets for primary controls; provide focus states and semantic labels.
- Use a consistent typography and spacing scale. Prefer one dominant primary action per screen.
- Support Hindi and English foundations; avoid hard-coded strings and design for text expansion.
- Never present demo fares, fake driver locations, fake ETAs or fake booking success as real.

## Customer screens
1. Launch/session restore: loading, unauthenticated, expired session and active-ride recovery.
2. Phone/OTP onboarding: resend cooldown, attempt limits, offline/error states.
3. Home/map: location rationale, denial/manual fallback, zoom/pan, accessible controls.
4. Pickup/destination: suggestions, reverse geocoding, manual pin, clear/edit invalidation and duplicate-place prevention.
5. Route preview: real route polyline, distance/ETA source and unavailable-route state.
6. Ride category: only categories serviceable in the selected zone; capacity and pickup estimate.
7. Quote review: itemized fare, currency, expiry, fees/taxes and clear estimate/confirmed distinction.
8. Request/searching: retry-safe request, cancellation policy, timeout and no-driver-found states.
9. Driver assigned: server-provided identity, vehicle/plate, ETA, masked contact and trip-sharing.
10. Driver arrived/start: server-verified pickup PIN.
11. In trip: status, route, location freshness, trip sharing and operationally supported safety actions.
12. Cancellation: reason/policy disclosure and conflict handling if ride status changed.
13. Completion: final server fare, payment status, receipt, rating and issue reporting.
14. Trips: loading/empty/error/pagination and details.
15. Support/safety: case ID/status and clear escalation expectations; no dead SOS button.
16. Profile/settings: language, notifications, privacy, data deletion, help and logout.

## Driver app screens
1. Phone login and driver terms.
2. Profile/vehicle/documents with upload progress, validation, pending/rejected/resubmit states.
3. Availability with server acknowledgement.
4. Ride offer with expiry, pickup distance, destination summary, payout/fare basis and accept/reject.
5. Server-authoritative offer expiration and duplicate-safe acceptance.
6. Pickup route, arrival and pickup PIN.
7. Active trip, network status and route fallback.
8. Completion acknowledgement and settlement status.
9. Trip history, earnings, support/safety and settings.
10. Clear location disclosures and collection only when operationally necessary.

## Admin console
- Responsive desktop-first layout, secure sign-in, least-privilege roles and MFA where feasible.
- Dashboard metrics include source and freshness; no fabricated live metrics.
- Driver verification with document access audit and reasoned decisions.
- Ride monitor with filters, authoritative event timeline and stale-location warnings.
- Support queue with assignment, priority, SLA, status, internal notes and escalation owner.
- Restricted safety case access and documented escalation.
- Fare/category/zone configuration with validation, effective dates, rollback and audit.
- Account restrictions include reason, duration, author and appeal path.
- Audit logs, role management and privacy-safe reports.

## Global states and acceptance
Every data-driven screen defines loading, success, empty, error, offline, permission-denied, stale-data and retry states. Every visible control has real behavior or is disabled with an explanation.
- Review light/dark contrast, small screens, large text and Hindi/English overflow.
- Verify accessibility labels, focus order and touch targets.
- Ensure no fake booking, route, ETA, safety response or admin metric.
- Request location only when needed and provide manual fallback.