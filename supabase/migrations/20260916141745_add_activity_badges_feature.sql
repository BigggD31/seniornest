-- "Show What's New" feature: per-user last-seen timestamps for Home and
-- Legacy tabs, used to compute a live badge count of new items on each
-- tab. Deliberately timestamp-based rather than a running counter column
-- -- avoids any increment/decrement race between concurrent viewers and
-- multiple devices, and the count is always derivable fresh from
-- feed_posts/legacy_entries rather than trusted to stay in sync on its
-- own.
--
-- Already applied directly to production via Supabase MCP on Sep 16
-- 2026 -- this file mirrors that change for repo history/future
-- environments, not a pending migration to run.

create table if not exists public.user_activity_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  home_last_seen_at timestamptz not null default now(),
  legacy_last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_activity_state enable row level security;

create policy "users_read_own_activity_state"
  on public.user_activity_state for select
  using (auth.uid() = user_id);

create policy "users_insert_own_activity_state"
  on public.user_activity_state for insert
  with check (auth.uid() = user_id);

create policy "users_update_own_activity_state"
  on public.user_activity_state for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Setup toggle: on by default, same convention as notify_messages /
-- notify_check_in / daily_checkin_enabled / meds_reminders_enabled.
alter table public.user_profiles
  add column if not exists show_activity_badges boolean not null default true;
