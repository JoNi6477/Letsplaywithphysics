-- =====================================================================
-- Let's Play With Physics — student accounts & access (Phase 1)
--
-- HOW TO RUN: Supabase dashboard → SQL Editor → New query →
-- paste this whole file → Run. Safe to run more than once.
--
-- Security model
--   * Every table has Row Level Security (RLS) switched on.
--   * Students can only read their own profile and their own enrollments.
--   * Only admins (people listed in public.admins) can grant or remove access
--     and manage plans. Nobody can make themselves an admin from the website;
--     admins are added only by running SQL here in the dashboard.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

-- One row per student, created automatically when they sign up.
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text not null default '',
  phone       text not null default '',
  created_at  timestamptz not null default now()
);

-- Who can use the admin page.
create table if not exists public.admins (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- What you sell. "unlocks" lists which kinds of content the plan opens:
-- 'mocks', 'videos', 'simulations'.
create table if not exists public.plans (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  description    text not null default '',
  price_inr      integer not null check (price_inr >= 0),
  duration_days  integer not null check (duration_days > 0),
  unlocks        text[] not null
                 check (cardinality(unlocks) > 0
                        and unlocks <@ array['mocks', 'videos', 'simulations']),
  is_active      boolean not null default true,
  sort_order     integer not null default 0,
  created_at     timestamptz not null default now()
);

-- A student's access to a plan between two dates.
create table if not exists public.enrollments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  plan_id     uuid not null references public.plans (id) on delete restrict,
  starts_at   timestamptz not null default now(),
  expires_at  timestamptz not null,
  source      text not null default 'manual' check (source in ('manual', 'razorpay')),
  amount_inr  integer not null default 0 check (amount_inr >= 0),
  note        text not null default '',
  granted_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  check (expires_at > starts_at)
);

create index if not exists enrollments_user_idx on public.enrollments (user_id, expires_at);


-- ---------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------

-- True when the logged-in user is an admin.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid()));
$$;

-- True when the logged-in user currently has access to a kind of content
-- ('mocks', 'videos' or 'simulations'). Later phases use this to protect content.
create or replace function public.has_access(kind text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.enrollments e
    join public.plans p on p.id = e.plan_id
    where e.user_id = (select auth.uid())
      and now() >= e.starts_at
      and now() <  e.expires_at
      and kind = any (p.unlocks)
  );
$$;

-- Create a profile automatically when someone signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name, phone)
  values (
    new.id,
    coalesce(new.email, ''),
    left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 80),
    left(coalesce(new.raw_user_meta_data ->> 'phone', ''), 20)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keep the profile email in sync if a student changes their email.
create or replace function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = coalesce(new.email, '') where id = new.id;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.handle_user_email_change();


-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------

alter table public.profiles    enable row level security;
alter table public.admins      enable row level security;
alter table public.plans       enable row level security;
alter table public.enrollments enable row level security;

-- profiles: students see and edit their own; admins see everyone.
drop policy if exists "profiles: read own or admin" on public.profiles;
create policy "profiles: read own or admin" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "profiles: update own" on public.profiles;
create policy "profiles: update own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- admins: no policies on purpose — only readable through is_admin().

-- plans: anyone can see active plans; admins can see and manage all.
drop policy if exists "plans: read active" on public.plans;
create policy "plans: read active" on public.plans
  for select to anon, authenticated
  using (is_active or (select public.is_admin()));

drop policy if exists "plans: admin insert" on public.plans;
create policy "plans: admin insert" on public.plans
  for insert to authenticated with check ((select public.is_admin()));

drop policy if exists "plans: admin update" on public.plans;
create policy "plans: admin update" on public.plans
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- enrollments: students see their own; only admins can change them.
drop policy if exists "enrollments: read own or admin" on public.enrollments;
create policy "enrollments: read own or admin" on public.enrollments
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "enrollments: admin insert" on public.enrollments;
create policy "enrollments: admin insert" on public.enrollments
  for insert to authenticated with check ((select public.is_admin()));

drop policy if exists "enrollments: admin update" on public.enrollments;
create policy "enrollments: admin update" on public.enrollments
  for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

drop policy if exists "enrollments: admin delete" on public.enrollments;
create policy "enrollments: admin delete" on public.enrollments
  for delete to authenticated using ((select public.is_admin()));


-- ---------------------------------------------------------------------
-- Permissions for the website (the project does not expose tables
-- automatically, so each one is granted here explicitly)
-- ---------------------------------------------------------------------

revoke all on public.profiles, public.admins, public.plans, public.enrollments from anon, authenticated;

grant select on public.plans to anon, authenticated;
grant insert, update on public.plans to authenticated;

grant select on public.profiles to authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

grant select, insert, update, delete on public.enrollments to authenticated;

-- is_admin() is also used by the public plans policy, so visitors need to run it
-- (it simply returns false for them).
revoke execute on function public.is_admin(), public.has_access(text) from public;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.has_access(text) to authenticated;
revoke execute on function public.handle_new_user(), public.handle_user_email_change() from public, anon, authenticated;


-- ---------------------------------------------------------------------
-- Starter plans (edit names and prices later from the admin page)
-- ---------------------------------------------------------------------

insert into public.plans (name, description, price_inr, duration_days, unlocks, sort_order)
select * from (values
  ('Mock Test Pass',   'All NEET & JEE Mains physics mock tests in the real NTA exam format.', 199, 90,  array['mocks'],                          1),
  ('Simulations Pack', 'All premium interactive physics simulations.',                          99,  90,  array['simulations'],                    2),
  ('Video Lectures',   'Full video lectures with notes (launching soon).',                      499, 180, array['videos'],                         3),
  ('All Access',       'Everything: mock tests, simulations and video lectures.',               999, 180, array['mocks', 'simulations', 'videos'], 4)
) as v (name, description, price_inr, duration_days, unlocks, sort_order)
where not exists (select 1 from public.plans);
