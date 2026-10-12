# Security Policy

## Reporting a vulnerability
Do not publish exploitable vulnerabilities, credentials, personal data, or production endpoints in public issues. Use GitHub's private security reporting feature (Security → Advisories → Report a vulnerability), if enabled, or a private contact channel supplied by the project owner.

## Secret handling
- Never commit Supabase service-role keys, database passwords, JWT signing secrets, payment or SMS-provider secrets, keystores, or production environment files.
- Mobile apps may contain only public/publishable Supabase keys. These are not authorization controls; Row Level Security and server-side authorization must enforce access.
- Treat every value compiled into an APK as extractable. Never put a service-role key in Flutter, Dart defines, assets, or mobile build secrets.
- If a credential is exposed, revoke/rotate it immediately and review access logs. Removing it in a later commit does not remove it from Git history.
- Use least-privilege CI permissions and store release signing material in GitHub Actions secrets.

## Release gates
Require secret/dependency scans, passing tests, review of database RLS and authorization, and a signed release build before production release. Compilation alone is not a production-readiness guarantee.
