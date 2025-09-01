-- Pain Management Diary - PostgreSQL Schema
-- This schema defines core tables: users, pain_events, providers, provider_access, fhir_exports
-- It uses public schema and sets up indexes, constraints, and audit timestamps.

-- Enable extensions if needed (UUIDs can also be generated via application if extension unavailable)
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- USERS: account and profile
CREATE TABLE IF NOT EXISTS public.users (
    id               BIGSERIAL PRIMARY KEY,
    email            VARCHAR(255) UNIQUE NOT NULL,
    password_hash    VARCHAR(255) NOT NULL,
    full_name        VARCHAR(255),
    timezone         VARCHAR(64) DEFAULT 'UTC',
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users (email);

-- PROVIDERS: healthcare providers that can access user data
CREATE TABLE IF NOT EXISTS public.providers (
    id               BIGSERIAL PRIMARY KEY,
    npi              VARCHAR(20), -- National Provider Identifier if available
    name             VARCHAR(255) NOT NULL,
    specialty        VARCHAR(255),
    organization     VARCHAR(255),
    contact_email    VARCHAR(255),
    contact_phone    VARCHAR(50),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_providers_npi ON public.providers (npi);
CREATE INDEX IF NOT EXISTS idx_providers_name ON public.providers (name);

-- PROVIDER ACCESS: permissions for providers to view user data
CREATE TABLE IF NOT EXISTS public.provider_access (
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    provider_id      BIGINT NOT NULL REFERENCES public.providers(id) ON DELETE CASCADE,
    access_level     VARCHAR(32) NOT NULL DEFAULT 'read', -- e.g., 'read', 'write'
    starts_at        TIMESTAMPTZ DEFAULT NOW(),
    expires_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, provider_id)
);

CREATE INDEX IF NOT EXISTS idx_provider_access_user ON public.provider_access (user_id);
CREATE INDEX IF NOT EXISTS idx_provider_access_provider ON public.provider_access (provider_id);

-- PAIN EVENTS: diary entries
CREATE TABLE IF NOT EXISTS public.pain_events (
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    occurred_at      TIMESTAMPTZ NOT NULL, -- when the pain was experienced
    recorded_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    severity         INTEGER NOT NULL CHECK (severity BETWEEN 0 AND 10),
    duration_minutes INTEGER CHECK (duration_minutes >= 0),
    location         VARCHAR(255), -- body location, e.g., 'head', 'lower back'
    triggers         TEXT,         -- comma separated or JSON string of triggers
    notes            TEXT,
    medications      TEXT,         -- medications taken related to the event
    mood             VARCHAR(64),
    activity_level   VARCHAR(64),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pain_events_user ON public.pain_events (user_id);
CREATE INDEX IF NOT EXISTS idx_pain_events_user_time ON public.pain_events (user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_pain_events_severity ON public.pain_events (severity);

-- FHIR EXPORTS: logs/records of exports in FHIR-HL7 format
CREATE TABLE IF NOT EXISTS public.fhir_exports (
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    provider_id      BIGINT REFERENCES public.providers(id) ON DELETE SET NULL,
    export_type      VARCHAR(64) NOT NULL, -- e.g., 'Observation', 'Bundle'
    format           VARCHAR(32) NOT NULL DEFAULT 'json', -- 'json' or 'xml'
    status           VARCHAR(32) NOT NULL DEFAULT 'pending', -- 'pending','success','failed'
    file_uri         TEXT,         -- where the export is stored (if persisted)
    request_payload  JSONB,        -- parameters of export request
    response_payload JSONB,        -- FHIR content or response details
    initiated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fhir_exports_user ON public.fhir_exports (user_id);
CREATE INDEX IF NOT EXISTS idx_fhir_exports_provider ON public.fhir_exports (provider_id);
CREATE INDEX IF NOT EXISTS idx_fhir_exports_status ON public.fhir_exports (status);

-- Triggers to auto-update updated_at timestamps
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_users_set_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'trg_providers_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_providers_set_updated_at
    BEFORE UPDATE ON public.providers
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'trg_provider_access_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_provider_access_set_updated_at
    BEFORE UPDATE ON public.provider_access
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'trg_pain_events_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_pain_events_set_updated_at
    BEFORE UPDATE ON public.pain_events
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM pg_trigger WHERE tgname = 'trg_fhir_exports_set_updated_at'
  ) THEN
    CREATE TRIGGER trg_fhir_exports_set_updated_at
    BEFORE UPDATE ON public.fhir_exports
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END$$;

-- Basic view to simplify provider-access joined lookups (optional convenience)
CREATE OR REPLACE VIEW public.v_user_provider_access AS
SELECT
  pa.id as provider_access_id,
  u.id  as user_id,
  u.email as user_email,
  p.id as provider_id,
  p.name as provider_name,
  pa.access_level,
  pa.starts_at,
  pa.expires_at
FROM public.provider_access pa
JOIN public.users u ON u.id = pa.user_id
JOIN public.providers p ON p.id = pa.provider_id;

-- Future growth:
-- - audit logs table
-- - refresh tokens/auth tables if backend needs DB-based sessions
