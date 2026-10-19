-- =====================================================================
-- Let's Play With Physics — protected mock tests (Phase 2)
--
-- HOW TO RUN: run schema.sql first (once). Then Supabase dashboard →
-- SQL Editor → New query → paste this whole file → Run.
-- Safe to run more than once (questions are only inserted the first time).
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
-- Starter tests and questions (inserted only once)
-- ---------------------------------------------------------------------

insert into public.tests (slug, title, exam, duration_min, is_active, sort_order) values
  ('neet-physics-1', 'NEET Physics — Full Mock 1', 'NEET', 60, true, 1),
  ('jee-physics-1', 'JEE Mains Physics — Mock 1', 'JEE Mains', 60, false, 2)
on conflict (slug) do nothing;

insert into public.questions (test_id, position, text, options, answer)
select t.id, v.position, v.text, v.options, v.answer
from (values
-- NEET Physics Mock 1 (45 questions)
  ('neet-physics-1', 1, $q$A body is moving with uniform velocity. The net force acting on it is:$q$, array[$q$Zero$q$, $q$Non-zero$q$, $q$Variable$q$, $q$Cannot be determined$q$], 0),
  ('neet-physics-1', 2, $q$The dimensional formula of surface tension is:$q$, array[$q$[MLT⁻²]$q$, $q$[ML⁻¹T⁻²]$q$, $q$[MT⁻²]$q$, $q$[ML²T⁻²]$q$], 2),
  ('neet-physics-1', 3, $q$A ball is thrown vertically upward with a speed of 20 m/s. The maximum height reached is (g = 10 m/s²):$q$, array[$q$10 m$q$, $q$20 m$q$, $q$40 m$q$, $q$30 m$q$], 1),
  ('neet-physics-1', 4, $q$Two projectiles are thrown with the same speed at angles of 30° and 60° with the horizontal. The ratio of their horizontal ranges is:$q$, array[$q$1 : √3$q$, $q$√3 : 1$q$, $q$1 : 1$q$, $q$1 : 2$q$], 2),
  ('neet-physics-1', 5, $q$A man of mass 60 kg stands in a lift accelerating upward at 2 m/s². His apparent weight is (g = 10 m/s²):$q$, array[$q$600 N$q$, $q$480 N$q$, $q$720 N$q$, $q$660 N$q$], 2),
  ('neet-physics-1', 6, $q$A 5 kg block rests on a horizontal surface with coefficient of static friction 0.4. The minimum horizontal force needed to just move it is (g = 10 m/s²):$q$, array[$q$20 N$q$, $q$50 N$q$, $q$2 N$q$, $q$12.5 N$q$], 0),
  ('neet-physics-1', 7, $q$If the momentum of a body is increased by 100%, its kinetic energy increases by:$q$, array[$q$300%$q$, $q$200%$q$, $q$100%$q$, $q$400%$q$], 0),
  ('neet-physics-1', 8, $q$The work done in stretching a spring of spring constant 200 N/m by 10 cm is:$q$, array[$q$2 J$q$, $q$10 J$q$, $q$1 J$q$, $q$0.5 J$q$], 2),
  ('neet-physics-1', 9, $q$A particle moves in a circle of radius 2 m with a constant speed of 4 m/s. Its centripetal acceleration is:$q$, array[$q$2 m/s²$q$, $q$16 m/s²$q$, $q$8 m/s²$q$, $q$4 m/s²$q$], 2),
  ('neet-physics-1', 10, $q$The moment of inertia of a thin ring of mass M and radius R about its diameter is:$q$, array[$q$½ MR²$q$, $q$MR²$q$, $q$(2/5) MR²$q$, $q$¼ MR²$q$], 0),
  ('neet-physics-1', 11, $q$When an ice skater pulls in her arms while spinning, which quantity remains constant?$q$, array[$q$Angular velocity$q$, $q$Angular momentum$q$, $q$Moment of inertia$q$, $q$Rotational kinetic energy$q$], 1),
  ('neet-physics-1', 12, $q$A solid sphere rolls without slipping. The fraction of its total kinetic energy that is rotational is:$q$, array[$q$2/5$q$, $q$2/7$q$, $q$5/7$q$, $q$1/2$q$], 1),
  ('neet-physics-1', 13, $q$The acceleration due to gravity at a height equal to the radius of the Earth (R) above its surface is:$q$, array[$q$g/2$q$, $q$g/9$q$, $q$g/4$q$, $q$g$q$], 2),
  ('neet-physics-1', 14, $q$The escape velocity from Earth is 11.2 km/s. For a planet with the same density but twice the radius of Earth, the escape velocity is:$q$, array[$q$11.2 km/s$q$, $q$5.6 km/s$q$, $q$44.8 km/s$q$, $q$22.4 km/s$q$], 3),
  ('neet-physics-1', 15, $q$If the orbital radius of a satellite becomes 4 times, its time period becomes:$q$, array[$q$4 times$q$, $q$8 times$q$, $q$16 times$q$, $q$2 times$q$], 1),
  ('neet-physics-1', 16, $q$A wire stretches by ΔL under a load. If both its length and radius are doubled, the extension under the same load becomes:$q$, array[$q$ΔL/2$q$, $q$2ΔL$q$, $q$ΔL$q$, $q$4ΔL$q$], 0),
  ('neet-physics-1', 17, $q$Bernoulli's theorem is based on the conservation of:$q$, array[$q$Energy$q$, $q$Momentum$q$, $q$Mass$q$, $q$Angular momentum$q$], 0),
  ('neet-physics-1', 18, $q$When water is heated from 0 °C to 10 °C, its volume:$q$, array[$q$First decreases, then increases$q$, $q$Decreases continuously$q$, $q$Increases continuously$q$, $q$First increases, then decreases$q$], 0),
  ('neet-physics-1', 19, $q$In an isothermal process of an ideal gas, the change in internal energy is:$q$, array[$q$Positive$q$, $q$Negative$q$, $q$Zero$q$, $q$Depends on pressure$q$], 2),
  ('neet-physics-1', 20, $q$The efficiency of a Carnot engine working between 527 °C and 127 °C is:$q$, array[$q$25%$q$, $q$40%$q$, $q$75%$q$, $q$50%$q$], 3),
  ('neet-physics-1', 21, $q$The temperature of a gas is raised from 27 °C to 927 °C. Its rms speed:$q$, array[$q$Doubles$q$, $q$Becomes 4 times$q$, $q$Halves$q$, $q$Remains the same$q$], 0),
  ('neet-physics-1', 22, $q$A mass m on a spring oscillates with time period T. If the mass is changed to 4m, the new time period is:$q$, array[$q$T/2$q$, $q$4T$q$, $q$√2 T$q$, $q$2T$q$], 3),
  ('neet-physics-1', 23, $q$The fundamental frequency of a pipe of length L closed at one end is (v = speed of sound):$q$, array[$q$v/4L$q$, $q$v/2L$q$, $q$v/L$q$, $q$2v/L$q$], 0),
  ('neet-physics-1', 24, $q$Two tuning forks of frequencies 256 Hz and 260 Hz are sounded together. The number of beats heard per second is:$q$, array[$q$516$q$, $q$2$q$, $q$8$q$, $q$4$q$], 3),
  ('neet-physics-1', 25, $q$The force between two point charges is F. If the distance between them is halved, the force becomes:$q$, array[$q$4F$q$, $q$2F$q$, $q$F/2$q$, $q$F/4$q$], 0),
  ('neet-physics-1', 26, $q$The SI unit of electric field is:$q$, array[$q$V·m$q$, $q$C/N$q$, $q$J/C$q$, $q$N/C$q$], 3),
  ('neet-physics-1', 27, $q$The electric field inside a charged hollow conducting sphere is:$q$, array[$q$Maximum at the centre$q$, $q$Zero$q$, $q$kq/R²$q$, $q$kq/R$q$], 1),
  ('neet-physics-1', 28, $q$Two capacitors of 4 μF each are connected in series. The equivalent capacitance is:$q$, array[$q$8 μF$q$, $q$2 μF$q$, $q$4 μF$q$, $q$1 μF$q$], 1),
  ('neet-physics-1', 29, $q$The energy stored in a 10 μF capacitor charged to 100 V is:$q$, array[$q$0.05 J$q$, $q$0.5 J$q$, $q$5 J$q$, $q$0.005 J$q$], 0),
  ('neet-physics-1', 30, $q$A wire of resistance R is stretched uniformly to double its length. Its new resistance is:$q$, array[$q$2R$q$, $q$R/2$q$, $q$R$q$, $q$4R$q$], 3),
  ('neet-physics-1', 31, $q$Kirchhoff's junction (current) law is based on the conservation of:$q$, array[$q$Energy$q$, $q$Mass$q$, $q$Momentum$q$, $q$Charge$q$], 3),
  ('neet-physics-1', 32, $q$The magnetic field at the centre of a circular loop of radius R carrying current I is:$q$, array[$q$μ₀I / 2πR$q$, $q$μ₀I / 4R$q$, $q$μ₀I / 2R$q$, $q$μ₀I / R$q$], 2),
  ('neet-physics-1', 33, $q$A proton and an alpha particle enter a uniform magnetic field perpendicularly with the same speed. The ratio of the radii of their paths (proton : alpha) is:$q$, array[$q$1 : 1$q$, $q$2 : 1$q$, $q$1 : 2$q$, $q$1 : 4$q$], 2),
  ('neet-physics-1', 34, $q$The magnetic susceptibility of a diamagnetic substance is:$q$, array[$q$Large and positive$q$, $q$Small and positive$q$, $q$Zero$q$, $q$Small and negative$q$], 3),
  ('neet-physics-1', 35, $q$Lenz's law is a consequence of the conservation of:$q$, array[$q$Charge$q$, $q$Energy$q$, $q$Momentum$q$, $q$Magnetic flux$q$], 1),
  ('neet-physics-1', 36, $q$In a purely inductive AC circuit, the current:$q$, array[$q$Lags the voltage by π/2$q$, $q$Leads the voltage by π/2$q$, $q$Is in phase with the voltage$q$, $q$Lags the voltage by π$q$], 0),
  ('neet-physics-1', 37, $q$At resonance in a series LCR circuit, the impedance is equal to:$q$, array[$q$Zero$q$, $q$Infinity$q$, $q$R$q$, $q$X_L + X_C$q$], 2),
  ('neet-physics-1', 38, $q$Which of the following electromagnetic waves has the highest frequency?$q$, array[$q$Infrared rays$q$, $q$UV rays$q$, $q$X-rays$q$, $q$Gamma rays$q$], 3),
  ('neet-physics-1', 39, $q$An object is placed 30 cm in front of a convex lens of focal length 20 cm. The image is formed at:$q$, array[$q$12 cm$q$, $q$30 cm$q$, $q$40 cm$q$, $q$60 cm$q$], 3),
  ('neet-physics-1', 40, $q$The power of a convex lens of focal length 25 cm is:$q$, array[$q$+25 D$q$, $q$−4 D$q$, $q$+0.25 D$q$, $q$+4 D$q$], 3),
  ('neet-physics-1', 41, $q$In Young's double slit experiment, if the slit separation is halved and the screen distance is doubled, the fringe width becomes:$q$, array[$q$Unchanged$q$, $q$Double$q$, $q$Four times$q$, $q$Half$q$], 2),
  ('neet-physics-1', 42, $q$The maximum kinetic energy of photoelectrons depends on the:$q$, array[$q$Intensity of incident light$q$, $q$Frequency of incident light$q$, $q$Time of exposure$q$, $q$Area of the metal surface$q$], 1),
  ('neet-physics-1', 43, $q$The ratio of the radius of the 2nd Bohr orbit to the 1st Bohr orbit in a hydrogen atom is:$q$, array[$q$2 : 1$q$, $q$1 : 4$q$, $q$4 : 1$q$, $q$1 : 2$q$], 2),
  ('neet-physics-1', 44, $q$The half-life of a radioactive sample is 10 days. The fraction of the sample remaining after 30 days is:$q$, array[$q$1/3$q$, $q$1/8$q$, $q$1/6$q$, $q$1/9$q$], 1),
  ('neet-physics-1', 45, $q$In an n-type semiconductor, the majority charge carriers are:$q$, array[$q$Holes$q$, $q$Electrons$q$, $q$Protons$q$, $q$Positive ions$q$], 1),
-- JEE Mains Physics sample (add more questions before switching this test on)
  ('jee-physics-1', 1, $q$A particle moves in a circle of radius r. The displacement after half a circle is:$q$, array[$q$0$q$, $q$2r$q$, $q$πr$q$, $q$r$q$], 1),
  ('jee-physics-1', 2, $q$The dimensional formula of Planck's constant is:$q$, array[$q$[ML²T⁻¹]$q$, $q$[MLT⁻²]$q$, $q$[ML²T⁻²]$q$, $q$[ML³T⁻¹]$q$], 0)
) as v (slug, position, text, options, answer)
join public.tests t on t.slug = v.slug
on conflict (test_id, position) do nothing;
