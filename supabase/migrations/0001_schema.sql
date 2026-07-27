-- ============================================================================
-- Gyaan LMS — Schema + Row Level Security
-- ============================================================================
-- Run this in the Supabase SQL editor (or via `supabase db push`) BEFORE seed.sql.
--
-- Design:
--   * Content tables (modules, module_examples, flashcard_decks, flashcards,
--     quiz_questions, badges) are readable by any authenticated user — they are
--     the curriculum. They are never written to from the client.
--   * Per-user tables (profiles, module_progress, quiz_attempts, point_events,
--     user_badges) are locked down with RLS so a user can only ever see and
--     mutate their own rows (row.user_id = auth.uid()).
-- ============================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users, holds the profession used for personalization)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  email        text,
  full_name    text,
  profession   text,                      -- e.g. 'recruitment', 'marketing'
  onboarded    boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Curriculum: modules teach the full surface of Claude
-- ---------------------------------------------------------------------------
create table if not exists public.modules (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  title         text not null,
  subtitle      text,
  feature_area  text not null,            -- 'chat', 'prompting', 'projects', ...
  order_index   int  not null,
  core_content  text not null,            -- markdown, profession-agnostic teaching
  icon          text,                     -- emoji shown in the UI
  accent        text,                     -- tailwind gradient key for vibrant cards
  points_reward int  not null default 100
);

-- Profession-specific worked example for a module. This is the personalization
-- layer: a recruiter and a marketer get genuinely different scenarios, prompts
-- and outcomes for the SAME underlying Claude feature.
create table if not exists public.module_examples (
  id           uuid primary key default gen_random_uuid(),
  module_id    uuid not null references public.modules (id) on delete cascade,
  profession   text not null,             -- 'recruitment', 'marketing', ...
  scenario     text not null,             -- the real-world situation
  sample_prompt text not null,            -- a prompt they could paste into Claude
  outcome      text not null,             -- what Claude gives back / why it helps
  unique (module_id, profession)
);

-- ---------------------------------------------------------------------------
-- Flashcards
-- ---------------------------------------------------------------------------
create table if not exists public.flashcard_decks (
  id          uuid primary key default gen_random_uuid(),
  module_id   uuid not null references public.modules (id) on delete cascade,
  title       text not null,
  order_index int not null default 0
);

create table if not exists public.flashcards (
  id          uuid primary key default gen_random_uuid(),
  deck_id     uuid not null references public.flashcard_decks (id) on delete cascade,
  profession  text,                       -- NULL = generic, shown to everyone
  front       text not null,
  back        text not null,
  order_index int not null default 0
);

-- ---------------------------------------------------------------------------
-- Quizzes
-- ---------------------------------------------------------------------------
create table if not exists public.quiz_questions (
  id            uuid primary key default gen_random_uuid(),
  module_id     uuid not null references public.modules (id) on delete cascade,
  profession    text,                     -- NULL = generic
  question      text not null,
  options       jsonb not null,           -- array of strings
  correct_index int not null,
  explanation   text,
  order_index   int not null default 0
);

-- ---------------------------------------------------------------------------
-- Per-user progress / activity
-- ---------------------------------------------------------------------------
create table if not exists public.module_progress (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  module_id    uuid not null references public.modules (id) on delete cascade,
  status       text not null default 'in_progress'
                 check (status in ('in_progress', 'completed')),
  best_score   int,
  quiz_total   int,
  started_at   timestamptz not null default now(),
  completed_at timestamptz,
  unique (user_id, module_id)
);

create table if not exists public.quiz_attempts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  module_id   uuid not null references public.modules (id) on delete cascade,
  score       int not null,
  total       int not null,
  answers     jsonb,
  created_at  timestamptz not null default now()
);

-- Brownie-points ledger. Total is sum(delta) for a user.
create table if not exists public.point_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  delta       int not null,
  reason      text not null,              -- 'module_completed', 'perfect_quiz', ...
  module_id   uuid references public.modules (id) on delete set null,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Badges (gamification)
-- ---------------------------------------------------------------------------
create table if not exists public.badges (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,
  name        text not null,
  description text not null,
  icon        text not null
);

create table if not exists public.user_badges (
  user_id    uuid not null references auth.users (id) on delete cascade,
  badge_id   uuid not null references public.badges (id) on delete cascade,
  awarded_at timestamptz not null default now(),
  primary key (user_id, badge_id)
);

-- ---------------------------------------------------------------------------
-- Auto-create a profile row when a new auth user signs up
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================================
-- Row Level Security
-- ============================================================================

-- Content tables: readable by any authenticated user, no client writes.
alter table public.modules          enable row level security;
alter table public.module_examples  enable row level security;
alter table public.flashcard_decks  enable row level security;
alter table public.flashcards       enable row level security;
alter table public.quiz_questions   enable row level security;
alter table public.badges           enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'modules','module_examples','flashcard_decks','flashcards','quiz_questions','badges'
  ] loop
    execute format(
      'drop policy if exists "read_content" on public.%I;', t);
    execute format(
      'create policy "read_content" on public.%I for select to authenticated using (true);', t);
  end loop;
end $$;

-- Profiles: a user can see and edit only their own profile.
alter table public.profiles enable row level security;
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (auth.uid() = id);

-- module_progress
alter table public.module_progress enable row level security;
drop policy if exists "mp_all_own" on public.module_progress;
create policy "mp_all_own" on public.module_progress
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- quiz_attempts
alter table public.quiz_attempts enable row level security;
drop policy if exists "qa_all_own" on public.quiz_attempts;
create policy "qa_all_own" on public.quiz_attempts
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- point_events
alter table public.point_events enable row level security;
drop policy if exists "pe_all_own" on public.point_events;
create policy "pe_all_own" on public.point_events
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- user_badges
alter table public.user_badges enable row level security;
drop policy if exists "ub_all_own" on public.user_badges;
create policy "ub_all_own" on public.user_badges
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
