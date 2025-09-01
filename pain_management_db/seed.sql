-- Optional seed data for local testing. Safe to run multiple times due to ON CONFLICT or WHERE NOT EXISTS.

-- Seed a demo user
INSERT INTO public.users (email, password_hash, full_name, timezone)
SELECT 'demo@example.com', '$2b$12$examplehashforlocaldevonly', 'Demo User', 'UTC'
WHERE NOT EXISTS (SELECT 1 FROM public.users WHERE email = 'demo@example.com');

-- Seed providers
INSERT INTO public.providers (npi, name, specialty, organization, contact_email)
SELECT '1234567890', 'Dr. Jane Smith', 'Pain Management', 'Health Clinic', 'jane.smith@clinic.test'
WHERE NOT EXISTS (SELECT 1 FROM public.providers WHERE npi = '1234567890');

INSERT INTO public.providers (npi, name, specialty, organization, contact_email)
SELECT '0987654321', 'Dr. John Doe', 'Neurology', 'City Hospital', 'john.doe@hospital.test'
WHERE NOT EXISTS (SELECT 1 FROM public.providers WHERE npi = '0987654321');

-- Link demo user to a provider with read access
INSERT INTO public.provider_access (user_id, provider_id, access_level, starts_at)
SELECT u.id, p.id, 'read', NOW()
FROM public.users u
JOIN public.providers p ON p.npi = '1234567890'
WHERE u.email = 'demo@example.com'
  AND NOT EXISTS (
    SELECT 1 FROM public.provider_access pa WHERE pa.user_id = u.id AND pa.provider_id = p.id
  );

-- Seed a few pain events for demo user
WITH demo_user AS (
  SELECT id AS user_id FROM public.users WHERE email = 'demo@example.com'
)
INSERT INTO public.pain_events (user_id, occurred_at, severity, duration_minutes, location, triggers, notes, medications, mood, activity_level)
SELECT user_id, NOW() - INTERVAL '1 day', 6, 45, 'lower back', 'sitting long,stress', 'Ache after long work day', 'ibuprofen 200mg', 'neutral', 'sedentary' FROM demo_user
UNION ALL
SELECT user_id, NOW() - INTERVAL '2 days', 8, 60, 'head', 'lack of sleep', 'Migraine-like pain', 'sumatriptan 50mg', 'low', 'sedentary' FROM demo_user
UNION ALL
SELECT user_id, NOW() - INTERVAL '3 days', 3, 20, 'neck', 'exercise', 'Mild stiffness improved with stretching', NULL, 'good', 'active' FROM demo_user;
