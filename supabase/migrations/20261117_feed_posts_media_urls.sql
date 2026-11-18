-- Nov 17 2026: a post can carry several photos (up to 10, swipeable on Home).
-- media_url still holds the first photo, so builds without multi-photo keep
-- working. media_urls holds the full ordered list and is only set when a post
-- has more than one photo. Applied to the live database as feed_posts_media_urls.
alter table public.feed_posts add column if not exists media_urls text[];
