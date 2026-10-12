# Security Policy

## Reporting a vulnerability
Please do not publish exploitable vulnerabilities, credentials, personal data, or production endpoints in public issues. Contact the repository owner privately through GitHub's security reporting feature (Security → Advisories → Report a vulnerability), if enabled, or use a private contact channel supplied by the project owner.

## Secret-handling rules
- Never commit Supabase service-role keys, database passwords, JWT signing secrets, payment secrets, SMS-provider secrets, keystores, or production environment files.
- Client apps may contain only public/publishable Supabase keys. These are not authorization controls: Row Level Security and server-side authorization must enforce access.
- Treat all values compiled into APKs as extractable. Never put a service-role key in Flutter, Dart defines, assets, or a mobile build secret.
- If a credential is exposed, revoke/rotate it immediately and review access logs; deleting it in a later commit does not remove it from Git history.
- Use least-privilege CI permissions and store release signing material in GitHub Actions secrets.

## Release gates
Before production release, require dependency and secret scans, passing tests, review of database RLS policies, backend authorization tests, and a signed release build. Do not represent a build as production-ready solely because it compiles.
