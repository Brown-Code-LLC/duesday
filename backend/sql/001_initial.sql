CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), apple_subject text UNIQUE NOT NULL, deletion_requested_at timestamptz);
CREATE TABLE email_accounts (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE, provider text NOT NULL, address text NOT NULL, status text NOT NULL, cursor text, watch_expires_at timestamptz);
CREATE TABLE oauth_tokens (account_id uuid PRIMARY KEY REFERENCES email_accounts(id) ON DELETE CASCADE, ciphertext text NOT NULL, iv text NOT NULL, tag text NOT NULL, wrapped_key text NOT NULL, wrap_iv text NOT NULL, wrap_tag text NOT NULL, key_id text NOT NULL, expires_at timestamptz);
CREATE TABLE devices (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE, apns_token_hash text UNIQUE NOT NULL, updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE webhook_events (id text PRIMARY KEY, provider text NOT NULL, received_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE audit_log (id bigserial PRIMARY KEY, user_id uuid REFERENCES users(id) ON DELETE SET NULL, action text NOT NULL, entity_type text NOT NULL, entity_id text, created_at timestamptz NOT NULL DEFAULT now());
