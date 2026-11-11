-- Nov 11 2026: let the poster of a plan show counts only instead of names
-- for Going / Maybe / Can't. Enforced in the database (like polls.hide_voters):
-- when on, nobody can read anyone else's answer, the poster included.
-- Existing plans stay as they are (default false).

alter table public.family_plans
  add column if not exists hide_rsvp_names boolean not null default false;

create or replace function public.plan_hides_rsvp_names(p_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce((select f.hide_rsvp_names from public.family_plans f where f.id = p_id), false);
$$;

drop policy if exists rsvps_read on public.plan_rsvps;
create policy rsvps_read on public.plan_rsvps
  for select
  using (
    can_see_family_item('plan'::text, plan_id)
    and (user_id = auth.uid() or not plan_hides_rsvp_names(plan_id))
  );

-- Counts only, for plans that hide names. Only people who can see the plan.
create or replace function public.plan_rsvp_counts(p_plan_id uuid)
returns table (going integer, maybe integer, cant integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select
    count(*) filter (where r.status = 'going')::int,
    count(*) filter (where r.status = 'maybe')::int,
    count(*) filter (where r.status = 'cant')::int
  from public.plan_rsvps r
  where r.plan_id = p_plan_id
    and public.can_see_family_item('plan', p_plan_id);
$$;

grant execute on function public.plan_rsvp_counts(uuid) to authenticated;
