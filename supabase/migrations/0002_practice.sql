-- ============================================================================
-- Gyaan LMS — Live Prompt Practice
-- ============================================================================
-- Adds the table backing the "Practice" tab: the learner writes a prompt for
-- their profession's scenario, it's sent to Claude, and Claude both answers it
-- and grades the prompt against a rubric. Run AFTER 0001_schema.sql.
-- ============================================================================

create table if not exists public.practice_attempts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  module_id     uuid not null references public.modules (id) on delete cascade,
  prompt        text not null,          -- what the learner wrote
  ai_response   text,                   -- how Claude answered their prompt
  score         int,                    -- rubric score 0..100
  strengths     jsonb,                  -- string[]
  improvements  jsonb,                  -- string[]
  created_at    timestamptz not null default now()
);

create index if not exists practice_attempts_user_module_idx
  on public.practice_attempts (user_id, module_id);

-- RLS: a learner sees and writes only their own attempts.
alter table public.practice_attempts enable row level security;
drop policy if exists "pa_practice_all_own" on public.practice_attempts;
create policy "pa_practice_all_own" on public.practice_attempts
  for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
