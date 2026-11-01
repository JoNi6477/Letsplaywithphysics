-- =====================================================================
-- Let's Play With Physics — protected mock tests (Phase 2)
--
-- HOW TO RUN: run schema.sql first (once). Then Supabase dashboard →
-- SQL Editor → New query → paste this whole file → Run.
-- Safe to run more than once.
--
-- What this does
--   * Questions and answers live in the database, not in the website code.
--   * Only students with an active plan that unlocks 'mocks' (or admins)
--     can load a test's questions — and never the answers.
--   * Answers are checked here on the server; the student only sees the
--     answer key after submitting. Every attempt is saved.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table if not exists public.tests (
  id            uuid primary key default gen_random_uuid(),
  slug          text not null unique check (slug ~ '^[a-z0-9-]+$'),
  title         text not null,
  exam          text not null check (exam in ('NEET', 'JEE Mains')),
  duration_min  integer not null check (duration_min > 0),
  marks_correct integer not null default 4,
  marks_wrong   integer not null default 1,
  is_active     boolean not null default true,
  sort_order    integer not null default 0,
  created_at    timestamptz not null default now()
);

create table if not exists public.questions (
  id        uuid primary key default gen_random_uuid(),
  test_id   uuid not null references public.tests (id) on delete cascade,
  position  integer not null check (position > 0),
  text      text not null,
  options   text[] not null check (cardinality(options) = 4),
  answer    integer not null check (answer between 0 and 3),
  unique (test_id, position)
);

create table if not exists public.attempts (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  test_id         uuid not null references public.tests (id) on delete cascade,
  answers         integer[] not null,
  score           integer not null,
  max_score       integer not null,
  correct         integer not null,
  wrong           integer not null,
  skipped         integer not null,
  time_taken_sec  integer not null check (time_taken_sec >= 0),
  submitted_at    timestamptz not null default now()
);

create index if not exists attempts_user_idx on public.attempts (user_id, submitted_at desc);


-- ---------------------------------------------------------------------
-- Functions the website calls
-- ---------------------------------------------------------------------

-- All switched-on tests, with question counts and the student's own best score.
create or replace function public.list_tests()
returns table (slug text, title text, exam text, duration_min integer, question_count integer,
               max_score integer, my_attempts integer, my_best integer)
language sql
stable
security definer
set search_path = ''
as $$
  select t.slug, t.title, t.exam, t.duration_min,
         (select count(*)::int from public.questions q where q.test_id = t.id),
         (select count(*)::int * t.marks_correct from public.questions q where q.test_id = t.id),
         (select count(*)::int from public.attempts a where a.test_id = t.id and a.user_id = (select auth.uid())),
         (select max(a.score) from public.attempts a where a.test_id = t.id and a.user_id = (select auth.uid()))
  from public.tests t
  where t.is_active
  order by t.sort_order, t.title;
$$;

-- The questions of one test WITHOUT the answers. Requires mock access.
create or replace function public.get_test(p_slug text)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  t public.tests;
begin
  if (select auth.uid()) is null then raise exception 'NOT_LOGGED_IN'; end if;
  if not (public.has_access('mocks') or public.is_admin()) then raise exception 'NO_ACCESS'; end if;
  select * into t from public.tests where slug = p_slug and (is_active or public.is_admin());
  if not found then raise exception 'TEST_NOT_FOUND'; end if;
  return json_build_object(
    'slug', t.slug, 'title', t.title, 'exam', t.exam, 'duration_min', t.duration_min,
    'marks_correct', t.marks_correct, 'marks_wrong', t.marks_wrong,
    'questions', coalesce((
      select json_agg(json_build_object('q', q.text, 'opts', q.options) order by q.position)
      from public.questions q where q.test_id = t.id), '[]'::json)
  );
end;
$$;

-- Marks a submitted test, saves the attempt, and returns the result with the answer key.
-- p_answers: one entry per question, 0-3 for options (1)-(4), -1 for not answered.
create or replace function public.submit_attempt(p_slug text, p_answers integer[], p_time_taken_sec integer)
returns json
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  t public.tests;
  key integer[];
  n integer;
  ans integer[];
  c integer := 0; w integer := 0; s integer := 0;
  new_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'NOT_LOGGED_IN'; end if;
  if not (public.has_access('mocks') or public.is_admin()) then raise exception 'NO_ACCESS'; end if;
  select * into t from public.tests where slug = p_slug and (is_active or public.is_admin());
  if not found then raise exception 'TEST_NOT_FOUND'; end if;

  select array_agg(q.answer order by q.position) into key from public.questions q where q.test_id = t.id;
  n := coalesce(cardinality(key), 0);
  if n = 0 then raise exception 'TEST_EMPTY'; end if;

  -- Normalise the answers: exactly n entries, anything invalid counts as not answered.
  ans := array(
    select case when i <= coalesce(cardinality(p_answers), 0) and p_answers[i] between 0 and 3
                then p_answers[i] else -1 end
    from generate_series(1, n) as i);

  for i in 1..n loop
    if ans[i] = -1 then s := s + 1;
    elsif ans[i] = key[i] then c := c + 1;
    else w := w + 1;
    end if;
  end loop;

  insert into public.attempts (user_id, test_id, answers, score, max_score, correct, wrong, skipped, time_taken_sec)
  values ((select auth.uid()), t.id, ans, c * t.marks_correct - w * t.marks_wrong, n * t.marks_correct, c, w, s,
          least(greatest(coalesce(p_time_taken_sec, 0), 0), t.duration_min * 60 + 120))
  returning id into new_id;

  return public.get_attempt_review(new_id);
end;
$$;

-- Full review of one of the student's own attempts (questions, their answers, the key).
create or replace function public.get_attempt_review(p_attempt_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  a public.attempts;
  t public.tests;
begin
  select * into a from public.attempts where id = p_attempt_id;
  if not found or not (a.user_id = (select auth.uid()) or public.is_admin()) then
    raise exception 'ATTEMPT_NOT_FOUND';
  end if;
  select * into t from public.tests where id = a.test_id;
  return json_build_object(
    'attempt_id', a.id, 'slug', t.slug, 'title', t.title, 'exam', t.exam,
    'score', a.score, 'max_score', a.max_score, 'correct', a.correct, 'wrong', a.wrong,
    'skipped', a.skipped, 'time_taken_sec', a.time_taken_sec, 'submitted_at', a.submitted_at,
    'questions', coalesce((
      select json_agg(json_build_object('q', q.text, 'opts', q.options, 'ans', q.answer,
                                        'chosen', a.answers[q.position]) order by q.position)
      from public.questions q where q.test_id = t.id), '[]'::json)
  );
end;
$$;


-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------

alter table public.tests     enable row level security;
alter table public.questions enable row level security;
alter table public.attempts  enable row level security;

-- tests: logged-in users can see switched-on tests; admins manage them.
drop policy if exists "tests: read active" on public.tests;
create policy "tests: read active" on public.tests
  for select to authenticated using (is_active or (select public.is_admin()));
drop policy if exists "tests: admin write" on public.tests;
create policy "tests: admin write" on public.tests
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- questions: admins only. Students get questions through get_test(), never the answers.
drop policy if exists "questions: admin only" on public.questions;
create policy "questions: admin only" on public.questions
  for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- attempts: students read their own; created only through submit_attempt().
drop policy if exists "attempts: read own or admin" on public.attempts;
create policy "attempts: read own or admin" on public.attempts
  for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));


-- ---------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------

revoke all on public.tests, public.questions, public.attempts from anon, authenticated;
grant select, insert, update, delete on public.tests, public.questions to authenticated;
grant select on public.attempts to authenticated;

revoke execute on function public.list_tests(), public.get_test(text),
  public.submit_attempt(text, integer[], integer), public.get_attempt_review(uuid) from public, anon;
grant execute on function public.list_tests(), public.get_test(text),
  public.submit_attempt(text, integer[], integer), public.get_attempt_review(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- Tests (inserted only once) — questions are added separately, see below
-- ---------------------------------------------------------------------

insert into public.tests (slug, title, exam, duration_min, is_active, sort_order) values
  ('neet-physics-1', 'NEET Physics — Full Mock 1', 'NEET', 60, true, 1),
  ('jee-physics-1', 'JEE Mains Physics — Mock 1', 'JEE Mains', 60, false, 2)
on conflict (slug) do nothing;

-- Questions and answers are NOT kept in this public repository — anyone can read
-- GitHub, so an answer key here would leak. Add questions in Supabase → SQL Editor
-- with a query like this (answer: 0 = option 1, 1 = option 2, 2 = option 3, 3 = option 4),
-- and keep your question files on your own computer:
--
-- insert into public.questions (test_id, position, text, options, answer)
-- select t.id, v.position, v.text, v.options, v.answer
-- from (values
--   ('neet-physics-2', 1, $q$Question text$q$, array[$q$A$q$, $q$B$q$, $q$C$q$, $q$D$q$], 0)
-- ) as v (slug, position, text, options, answer)
-- join public.tests t on t.slug = v.slug
-- on conflict (test_id, position) do nothing;
