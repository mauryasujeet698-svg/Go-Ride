# Go-Ride Security and Privacy Threat Model

## Assets
Phone numbers/profile data; exact pickup/drop-off and driver location; ride history; driver identity/vehicle documents; ride-start PIN; fare quote/payment status; refresh tokens; support/safety case contents; admin credentials and audit history.

## Trust boundaries
1. Android app ↔ public API.
2. API ↔ database/cache/event delivery.
3. Driver app ↔ location/dispatch service.
4. Backend ↔ SMS/OTP, map/routing, push and payment providers.
5. Admin console ↔ privileged APIs and document storage.
6. Build pipeline ↔ repository, dependencies, signing keys and artifacts.

## Threats and controls
| Threat | Required control/evidence |
|---|---|
| OTP brute force/SMS pumping/account takeover | Per-phone/device/IP throttles, cooldown, attempt limit, abuse monitoring and provider spend alerts. |
| Forged role or IDOR | Server-side ownership/role checks on every object/action; rider-vs-driver-vs-admin negative tests. |
| Fake fare/quote tampering | Server-computed quote, opaque ID, expiry, currency, pricing-policy version and server validation. |
| Duplicate booking | Persisted idempotency key and request hash; duplicate returns original result; key reuse with different payload rejected. |
| Driver assigned to two rides | Atomic transactional dispatch claim and concurrency tests. |
| Cancellation/accept race | Conditional server transition with version; conflict returns authoritative snapshot. |
| Forged/stale driver location | Validate time, accuracy, impossible jumps, active duty and freshness. |
| Ride-start PIN guessing/disclosure | Server validation, expiry, attempt limits and no logs/analytics. |
| Token theft | Short-lived access tokens, refresh rotation/revocation, secure device storage, TLS and redacted logs. |
| Document exposure | Private object storage, short-lived access, least privilege, access audit and retention policy. |
| PII/location leaked into logs | Structured logging/redaction tests; do not log OTPs, tokens or unnecessary coordinates. |
| CI/dependency compromise | Minimal workflow permissions, dependency review/scanning, protected main, secret scanning and release provenance. |
| Fake/unattended SOS | No launch until ownership, escalation routing, hours, monitoring, runbook and end-to-end tests exist. |
| Payment webhook replay/spoofing | Verify provider signature, idempotent event handling, amount/currency checks and reconciliation. |
| Admin misuse | Least privilege, MFA where feasible, audited decisions and alerts for high-risk actions. |
| Data retained after deletion | Retention matrix, documented legal exceptions, deletion workflow and verification tests. |

## Privacy principles
- Collect precise location only when needed and explain why.
- Driver background location requires clear disclosure and platform permission, only while operationally necessary.
- Restrict location visibility to relevant active-trip participants and authorized support/admin roles.
- Separate operational logs from customer-visible support notes.
- Define retention periods for location traces, ride records, documents and support cases before launch.
- Provide access/deletion workflows and disclose lawful exceptions.
- Avoid sensitive analytics payloads and unnecessary third-party SDKs.
- Maintain vendor inventory, data-processing terms and breach contacts.

## Release verification
Use OWASP MASVS/MASTG as references across storage, crypto, authentication, network, platform, code, resilience and privacy. Do not claim compliance without documented verification. Review API authorization, mobile storage/network behavior, dependencies, logs, backup/restore and abuse limits.