-- Keep-alive migration: adds a last_active_at column to user_profiles to track activity
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

-- Update existing rows to set last_active_at
UPDATE public.user_profiles
SET last_active_at = CURRENT_TIMESTAMP
WHERE last_active_at IS NULL;
