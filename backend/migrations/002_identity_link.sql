BEGIN;
ALTER TABLE app_users ADD COLUMN IF NOT EXISTS auth_issuer text;
ALTER TABLE app_users ADD COLUMN IF NOT EXISTS auth_subject text;
CREATE UNIQUE INDEX IF NOT EXISTS app_users_auth_identity_unique
 ON app_users(auth_issuer, auth_subject)
 WHERE auth_issuer IS NOT NULL AND auth_subject IS NOT NULL;
COMMIT;
