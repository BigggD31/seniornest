-- Favs (bookmarks) become per-Nest instead of per-person.
-- Additive and safe with older app builds: they simply ignore the new column.

-- 1. New column. Nullable so older builds that don't send it keep working.
alter table public.user_favourites
  add column if not exists nest_id uuid references public.nests(id) on delete cascade;

-- 2. Backfill: tag each existing bookmark with the Nest its item lives in.
update public.user_favourites f
   set nest_id = fp.nest_id
  from public.feed_posts fp
 where f.nest_id is null
   and fp.id::text = f.item_id;

update public.user_favourites f
   set nest_id = le.nest_id
  from public.legacy_entries le
 where f.nest_id is null
   and le.id::text = f.item_id;

-- 3. Anything left (sample placeholders, deleted posts): attach to the
--    person's earliest Nest so single-Nest people keep what they saved.
update public.user_favourites f
   set nest_id = (
     select m.nest_id
       from public.nest_members m
      where m.user_id = f.user_id
      order by m.joined_at asc
      limit 1
   )
 where f.nest_id is null;

create index if not exists user_favourites_user_nest_idx
  on public.user_favourites (user_id, nest_id);
