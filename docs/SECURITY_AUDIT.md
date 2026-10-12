# Go Ride security audit — backend changes deferred

**Scope:** static review of the checked-in Supabase schema and Flutter client only. No hosted backend was accessed or modified, and this document is not a penetration test.

## Findings requiring backend review

1. **Privileged database functions:** the schema contains 11 `SECURITY DEFINER` functions without an explicit function-level `SET search_path`. Review each function's object references, owner, execute grants, authorization checks, and caller-controlled inputs. Add a safe fixed search path and schema-qualify referenced objects where appropriate.
2. **Broad read policies:** four tables have `SELECT USING (true)` policies: `drives`, `profile_features`, `profiles`, and `reviews`. Some public ride/profile/review fields may be intentional, but the policy must be checked against each table's sensitive columns and intended anonymous access. Prefer safe public views or column-limited API exposure where needed.
3. **Client-side trust boundary:** Supabase anon keys and Firebase client configuration are extractable from a distributed app. Authorization must be enforced by RLS and server-side functions; a client check is not a security boundary.
4. **Production configuration:** the Android package ID and Firebase registration are coupled. This rebrand deliberately preserves the current ID and Supabase redirect scheme to avoid breaking sign-in and push notifications.

## Required before production

- Map every table, policy, trigger and RPC to its legitimate user/admin operations.
- Test anonymous, authenticated, cross-user and admin access, including blocked accounts and push-token ownership.
- Review storage bucket policies and auth redirect allow-lists.
- Add tests for atomic ride/seat assignment, duplicate requests, authorization failures, and concurrent requests.
- Apply reviewed migrations to a staging project first; deploy only after explicit approval.

**Status:** findings documented, not remediated in the hosted backend. Backend hardening is deferred as requested.
