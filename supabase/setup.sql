-- ============================================================================
-- Gyaan — ONE-PASTE setup for the Supabase SQL Editor.
-- Paste this whole file and Run. It creates the schema, RLS, the practice
-- table, and loads the full curriculum. Safe to re-run (seed clears content).
-- Generated from supabase/migrations/*.sql + supabase/seed.sql — do not edit here.
-- ============================================================================

-- ===== 0001_schema.sql =====
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

-- ===== 0002_practice.sql =====
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

-- ===== 0003_variety.sql =====
-- ============================================================================
-- Gyaan LMS — Learning variety: difficulty tiers, question/card kinds, hints
-- ============================================================================
-- Backs the "professional teacher" pass: bigger content pools with difficulty
-- levels (beginner/intermediate/advanced) and multiple question/card formats,
-- so each session's Flashcards and Quiz draw a fresh randomized subset instead
-- of always showing the same fixed set in the same order. Run AFTER 0002.
-- ============================================================================

-- Flashcards: difficulty tier + a card "pattern" so review doesn't always feel
-- the same shape (a scenario card, a reverse-recall card, a plain concept card).
alter table public.flashcards
  add column if not exists difficulty text not null default 'beginner'
    check (difficulty in ('beginner', 'intermediate', 'advanced')),
  add column if not exists card_type text not null default 'concept'
    check (card_type in ('concept', 'scenario', 'reverse'));

-- Quiz questions: difficulty tier, a question "kind" for variety, and an
-- optional teacher-style hint the learner can reveal before answering.
-- Scoring stays uniform (options[] + correct_index) for every kind — kind only
-- changes how the question is framed and rendered, keeping grading free and
-- instant (no LLM needed to grade a multiple-choice / true-false / fill-blank
-- answer).
alter table public.quiz_questions
  add column if not exists difficulty text not null default 'beginner'
    check (difficulty in ('beginner', 'intermediate', 'advanced')),
  add column if not exists kind text not null default 'mcq'
    check (kind in ('mcq', 'true_false', 'scenario', 'fill_blank')),
  add column if not exists hint text;

create index if not exists flashcards_module_difficulty_idx
  on public.flashcards (deck_id, difficulty);
create index if not exists quiz_questions_module_difficulty_idx
  on public.quiz_questions (module_id, difficulty);

-- ===== seed.sql =====
-- ============================================================================
-- Gyaan LMS — Seed data (curriculum + personalization)
-- ============================================================================
-- Idempotent: safe to re-run. Deletes content tables in FK-safe order, then
-- re-inserts. Per-user tables are never touched.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Clean slate (FK-safe order)
-- ---------------------------------------------------------------------------
delete from public.flashcards;
delete from public.flashcard_decks;
delete from public.quiz_questions;
delete from public.module_examples;
delete from public.modules;
delete from public.badges;

-- ===========================================================================
-- MODULES
-- ===========================================================================
insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'chat-basics',
  'Meet Claude: Chat Basics',
  'Conversations, context, and how to talk to Claude',
  'chat',
  1,
  E'Claude is an AI assistant you talk to in plain language — no special syntax, no menus. You type what you need, Claude responds, and you keep going. The whole interaction is a **conversation**, and that turn-by-turn structure is the single most important thing to understand.\n\n**Context is everything.** Claude reads your entire conversation each time it replies — every message you have sent and every message it has sent back. This shared history is called the *context window*. Because Claude remembers what was said earlier in the thread, you can say "make it shorter" or "use a more formal tone" without repeating yourself. Start a brand-new chat and that memory is gone — Claude begins fresh with no knowledge of your previous threads.\n\n**Iterate, do not restart.** The best results almost never come from the first message. Treat Claude like a capable colleague: give it a first draft request, then refine. "Good, but cut the jargon." "Add a line about pricing." "Now turn it into three bullet points." Each follow-up builds on everything before it.\n\n**Give Claude a role and a goal.** A quick line like "You are helping me, a busy professional, do X for audience Y" sharply improves the response. Claude adapts its tone, depth, and format to whatever you tell it about the situation.\n\n- **One chat = one topic.** Keep unrelated tasks in separate conversations so the context stays clean.\n- **Longer is not always better** — but relevant detail always helps. Paste the actual email, the real data, the exact error.\n- **Ask Claude to ask you questions** ("what do you need to know from me?") when you are not sure what to include.',
  '💬',
  'from-sky-500 to-indigo-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'prompting',
  'Prompting Fundamentals',
  'Be specific, give context, show examples',
  'prompting',
  2,
  E'A *prompt* is simply the instruction you give Claude. Vague prompts get generic answers — specific prompts get useful ones. Prompting is a skill, and a handful of habits will take you most of the way there.\n\n**1. Be specific about the outcome.** Instead of "write about our product," say "write a 120-word LinkedIn post announcing our product to operations managers, friendly but not salesy, ending with a question." State the length, audience, tone, and format you want. Claude cannot read your mind — but it is very good at following clear direction.\n\n**2. Give context.** Paste the source material: the data, the previous email, the transcript, the brand guidelines. Claude reasons from what you provide. The more relevant raw material it has, the less it has to guess.\n\n**3. Show an example.** If you have a sample of the style or format you want ("here is a headline I loved — write five more like it"), include it. Showing one good example is often worth a paragraph of description. This is called *few-shot* prompting.\n\n**4. Tell Claude who to be.** A role primer — "act as a skeptical CFO reviewing this" — shapes the whole response.\n\n**5. Ask for structure.** Request a table, numbered steps, or a specific template and Claude will format accordingly.\n\n- **Split big asks into steps.** "First outline it, then we will draft each section."\n- **Say what to avoid** as clearly as what you want ("no buzzwords, no exclamation marks").\n- **If the answer misses, do not just rephrase — add the missing constraint.** Nine times out of ten the fix is more context, not different wording.',
  '✍️',
  'from-fuchsia-500 to-pink-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'projects',
  'Projects & Persistent Context',
  'Reusable knowledge and custom instructions',
  'projects',
  3,
  E'A single chat forgets everything the moment you close it. **Projects** solve that. A Project is a dedicated workspace that bundles together custom instructions and reference files, so every conversation you start inside it already knows your context.\n\n**Custom instructions** are standing orders that apply to every chat in the Project — your tone of voice, your audience, your rules ("always use British spelling," "never promise delivery dates," "we are a B2B company selling to hospitals"). You set them once instead of repeating them in every message.\n\n**Project knowledge** is the set of documents you upload once and reuse forever: style guides, product specs, past reports, templates, policy PDFs. Claude can draw on all of it in any conversation in that Project. Ask a question and the answer is grounded in *your* material, not generic web knowledge.\n\n**Why it matters:** Projects turn Claude from a smart stranger into a colleague who already knows how your team works. Output becomes consistent across everyone using the Project, and onboarding a task takes seconds because the background is already loaded.\n\n- **One Project per recurring context** — a client, a product line, a function.\n- **Keep knowledge current.** Remove stale docs so Claude does not cite outdated information.\n- **Custom instructions beat repetition.** If you find yourself typing the same preamble every time, move it into the Project instructions.\n- Individual chats inside a Project still have their own separate context — the Project shares knowledge and instructions, not conversation history between chats.',
  '📁',
  'from-emerald-500 to-teal-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'artifacts',
  'Artifacts: Build Real Things',
  'Documents, apps, and visuals you can edit live',
  'artifacts',
  4,
  E'Sometimes you do not want an answer *in* the chat — you want a thing you can keep, edit, and share. That is an **Artifact**: a standalone piece of content that opens in its own panel beside the conversation. Documents, tables, code, charts, small web apps — all live as Artifacts.\n\n**Artifacts are editable and versioned.** Claude generates a first version — you say "make the header blue" or "add a fourth column" and Claude updates the same Artifact in place. You are not copying text back and forth — you are iterating on a living document.\n\n**Claude can build working software.** Ask for a calculator, an interactive dashboard, or a form and Claude writes real HTML/JavaScript that actually runs in the Artifact panel. You can click the buttons and see it work, then refine it by describing changes in plain language.\n\n**Great Artifact candidates:**\n- Polished documents (briefs, one-pagers, reports) you want to export.\n- Tables and comparison matrices you will keep tweaking.\n- Interactive tools — calculators, quizzes, mockups, dashboards.\n- Diagrams and charts that visualize your data.\n\n**How to get good Artifacts:** describe the purpose and audience, then iterate. "Build me a one-page pricing sheet" gets you a start — "make it two columns, add a FAQ, use our blue" gets you the finished piece. Because it is a real document, you can copy it out, download it, or share it when it is ready.',
  '🎨',
  'from-amber-500 to-orange-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'tool-use',
  'Tool Use & Connectors',
  'Let Claude search, browse, and use your tools',
  'tools',
  5,
  E'On its own, Claude reasons from its training and from what you paste in. **Tools and connectors** let it reach beyond that — to fetch live information and act in the systems you already use.\n\n**Web search** lets Claude look things up in real time. Ask about a recent announcement, current pricing, or this quarter''s news and Claude searches, reads the results, and answers with up-to-date information and links — instead of relying on what it learned during training.\n\n**Connectors** link Claude to your own tools: Google Drive, Gmail, GitHub, Slack, calendars, and many more. Once connected, Claude can pull a document from your Drive, read a thread, or reference a file without you copy-pasting it. Some connectors are read-only — others let Claude take actions, always within the permissions you grant.\n\n**The Model Context Protocol (MCP)** is the open standard that makes this extensible — teams can plug their own internal systems into Claude the same way.\n\n**Why it matters:** tools close the gap between "Claude gives good advice" and "Claude does the task using my real data and current facts."\n\n- **Ask Claude to search** when a fact might be recent or when you need a source you can verify.\n- **Verify what matters.** Tools reduce guesswork, but you still check anything high-stakes — click the links Claude cites.\n- **Grant only the access you need.** Connect the tools relevant to a task and review permissions.\n- **Be explicit:** "search the web for X," "check the file in my Drive called Y," so Claude uses the right tool for the job.',
  '🔌',
  'from-violet-500 to-purple-400',
  100
);

insert into public.modules (slug, title, subtitle, feature_area, order_index, core_content, icon, accent, points_reward)
values (
  'workflows',
  'Putting It Together: Real Workflows',
  'Chaining Claude into your daily work',
  'workflows',
  6,
  E'The real payoff comes when you stop using Claude for one-off questions and start building **workflows** — repeatable sequences where each step feeds the next. This module ties together everything before it: chat, prompting, Projects, Artifacts, and tools.\n\n**Chain the steps.** Most real work is a pipeline, not a single ask. Research → outline → draft → refine → format → repurpose. Do it as a conversation: each Claude output becomes the input to the next step, and you steer at every stage.\n\n**Anchor the workflow in a Project** so the context (your voice, your rules, your reference docs) is loaded automatically every time you run it. Reach for **tools** when a step needs live data, and produce **Artifacts** for the deliverables you will keep or share.\n\n**Make it repeatable.** Once a workflow works, save the sequence of prompts. Next time it is a template you fill in, not a blank page. Many people keep a note of their best prompt chains for recurring tasks.\n\n**Keep a human in the loop.** Claude drafts, accelerates, and organizes — you decide, verify, and own the result. The goal is not to remove your judgment but to remove the busywork around it.\n\n- **Start where it hurts most** — the recurring task you dread. Automate that first.\n- **Break it into stages** and get each stage right before chaining them.\n- **Reuse and refine.** Every good prompt chain you save compounds over time.',
  '🚀',
  'from-rose-500 to-red-400',
  100
);

-- ===========================================================================
-- MODULE EXAMPLES  (6 modules x 6 professions = 36 rows)
-- ===========================================================================

-- ---- chat-basics ----------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='chat-basics'), 'recruitment',
 'You are sourcing senior backend engineers for a fintech client and need to send a first-touch message that does not read like every other recruiter''s. You want to draft one, then adjust the tone in the same thread until it feels human.',
 E'I''m a technical recruiter reaching out to a senior backend engineer at a competitor. Draft a short LinkedIn first message (under 90 words) for a fintech role — warm, specific, no buzzwords, and mention that the team owns payments infrastructure. Then wait, I''ll ask you to adjust the tone.',
 'Claude returns a tight outreach message, then refines it turn by turn as you ask for a warmer opener or a softer call to action — all without you re-explaining the role.'),
((select id from public.modules where slug='chat-basics'), 'marketing',
 'A product launch is three weeks out and you need a batch of tagline options for the campaign. You want to brainstorm out loud with Claude, react to what you like, and narrow down inside one conversation.',
 E'I''m a marketing manager launching a project-management app for small agencies. Give me 10 punchy tagline options — mix playful and confident. After I react, we''ll refine the ones I like.',
 'Claude produces a varied first batch, then hones in on your favorites as you give feedback, keeping every earlier idea in context so directions build on each other.'),
((select id from public.modules where slug='chat-basics'), 'sales',
 'You just finished a 45-minute discovery call and jotted messy notes. You need a clean recap and a follow-up email before the prospect goes cold, and you want to tweak the email''s tone before sending.',
 E'Here are my rough notes from a discovery call with a mid-market retail prospect: [paste notes]. Summarize the key pains and next steps, then draft a follow-up email that references two specific things they said. Keep it concise and consultative.',
 'Claude turns raw notes into a structured recap plus a personalized follow-up, and you refine the email''s tone in the same thread — cutting post-call admin from 20 minutes to two.'),
((select id from public.modules where slug='chat-basics'), 'engineering',
 'A deploy failed and you are staring at an unfamiliar stack trace at 6pm. You want to understand what it means and what to check first, asking follow-up questions as you narrow it down.',
 E'I got this error deploying a Node service: [paste stack trace]. Explain in plain terms what''s likely going wrong and the three most likely causes, ordered by probability. I''ll ask follow-ups as I check each one.',
 'Claude interprets the trace, ranks likely causes, and stays in context as you rule things out — acting like a pair-programmer who remembers everything you have tried so far.'),
((select id from public.modules where slug='chat-basics'), 'hr',
 'Leadership is changing the remote-work policy and you must announce it company-wide. The message needs to feel supportive, not corporate, and you want to test a few tones before it goes out.',
 E'I''m an HR partner announcing that we''re moving from fully remote to three days in-office. Draft a company-wide message that acknowledges this is a big change, explains the why honestly, and stays warm. Then I''ll ask you to make it less corporate.',
 'Claude drafts an empathetic announcement and adjusts warmth and directness on request, letting you find the right tone for a sensitive change without starting over.'),
((select id from public.modules where slug='chat-basics'), 'finance',
 'Your monthly management report shows marketing spend 18% over budget and the CFO wants an explanation by tomorrow. You want to reason through the variance with Claude and ask clarifying follow-ups.',
 E'Our monthly report shows marketing opex came in 18% over budget. Here''s the breakdown by line item: [paste figures]. Help me identify which lines drove the overage and draft three plausible explanations I can verify. I''ll ask follow-ups as I dig in.',
 'Claude pinpoints the lines driving the variance and proposes explanations to check, then refines the narrative as you feed it more detail — turning a spreadsheet into a story the CFO can read.');

-- ---- prompting ------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='prompting'), 'recruitment',
 'You need to write a job description that actually attracts the right people. Your last one was generic and drew unqualified applicants, so this time you give Claude the specifics and an example of a JD you admire.',
 E'Write a job description for a Senior Data Analyst. Context: remote-first SaaS company, 200 people, reports to Head of Analytics, must know SQL + dbt + Looker, salary band 95-120k. Tone: direct and human, no "rockstar" clichés. Match the style of this JD I like: [paste example]. Include a 5-bullet "what you''ll do" and a short "what we offer".',
 'By giving role specifics plus a style example, you get a JD in your target voice with the right structure — not a generic template you have to rewrite.'),
((select id from public.modules where slug='prompting'), 'marketing',
 'A batch of ad copy came back flat and off-brand. You decide to prompt properly this time: brand voice, audience, constraints, and an example of a headline that performed well.',
 E'Rewrite this ad copy for a Meta campaign. Audience: busy parents shopping for meal kits. Brand voice: warm, no hype, plain language, never use the word "delicious". Constraint: primary text under 125 characters. Here''s a headline that crushed last quarter as a style reference: "Dinner, minus the 5pm panic." Give me 6 variations.',
 'With audience, voice rules, a hard length limit, and a proven example, Claude returns on-brand variations that fit the ad platform — usable without a rewrite.'),
((select id from public.modules where slug='prompting'), 'sales',
 'Your cold emails get ignored. You want Claude to write one that is specific and personalized, so you supply the prospect''s context and paste a past email that actually booked meetings.',
 E'Write a cold email to a VP of Operations at a 500-person logistics firm. Trigger: they just announced expansion into a new region. Value prop: our software cuts route-planning time by 30%. Rules: under 90 words, one clear ask, no "hope this finds you well". Model it on this email that booked 4 meetings: [paste example].',
 'Claude produces a concise, trigger-based email in your proven style, giving you a personalized opener and a single clear ask instead of a generic template.'),
((select id from public.modules where slug='prompting'), 'engineering',
 'You need a utility function and want it right the first time. Instead of a vague ask, you specify the language, inputs, edge cases, and constraints precisely.',
 E'Write a TypeScript function `parseDuration(input: string): number` that converts strings like "1h30m", "45m", "2h" into total seconds. Requirements: handle hours and minutes only, return 0 for invalid input (don''t throw), no external libraries, include JSDoc and three example calls. Then list the edge cases you handled.',
 'A precise spec with inputs, edge cases, and constraints yields code that compiles and matches your requirements — plus a list of handled edge cases so you can review quickly.'),
((select id from public.modules where slug='prompting'), 'hr',
 'You are hiring for a role and need structured interview questions that map to real competencies, with a scoring rubric — not a random list off the internet.',
 E'Create a behavioral interview guide for a Customer Success Manager role. Competencies to assess: empathy, handling churn risk, cross-functional influence. For each, give 2 questions and a 1-3 scoring rubric describing what a weak, average, and strong answer sounds like. Keep questions open-ended and legally safe.',
 'By naming the competencies and asking for a rubric, you get a structured, defensible interview guide interviewers can score consistently — not just a question list.'),
((select id from public.modules where slug='prompting'), 'finance',
 'You need to explain how to build a specific model and want Claude''s output grounded in your actual numbers, with the formula logic spelled out step by step.',
 E'Explain how to build a 3-statement driver in Excel that links revenue growth to headcount. Assumptions: revenue $12M, 15% YoY growth, revenue-per-head target $250k. Show the exact formulas cell by cell, state each assumption explicitly, and flag where I''d normally sanity-check the output.',
 'With concrete assumptions and a request for cell-level formulas, Claude returns a precise, auditable walkthrough you can drop into a model instead of vague guidance.');

-- ---- projects -------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='projects'), 'recruitment',
 'You write dozens of outreach messages and offer letters a week, and they should all sound like your company. You set up a Project with your employer-brand materials so every draft is on-message automatically.',
 E'Custom instructions for this Project: "You help our talent team. Always match our employer brand: candid, human, no corporate jargon. Never over-promise on comp or timelines." I''ll upload our EVP one-pager, benefits summary, and three example messages. From now on, when I ask for outreach, ground it in these.',
 'Every chat in the Project starts already knowing your employer brand and benefits, so outreach and offer drafts are consistent across the whole recruiting team without re-briefing.'),
((select id from public.modules where slug='projects'), 'marketing',
 'Five people touch your brand''s content and it shows — voice drifts, terms vary. You create a brand Project holding your style guide and messaging framework so every asset comes out on-brand.',
 E'Set up this Project to enforce our brand. Custom instructions: "Follow the uploaded style guide exactly — voice, banned words, and formatting. We are B2B, sell to HR leaders." Knowledge: I''m adding the style guide, tone-of-voice doc, and our messaging pillars. When I ask for any asset, apply all of it.',
 'Anyone on the team can generate blog posts, emails, or social copy that follow the same voice and rules, because the brand system lives in the Project instead of in one person''s head.'),
((select id from public.modules where slug='projects'), 'sales',
 'Reps keep answering objections inconsistently and pricing questions get fumbled. You build a sales-enablement Project with your product one-pagers, pricing, and objection-handling playbook.',
 E'Create a Project for our sales team. Custom instructions: "You are a sales assistant. Only use the uploaded materials for product facts and pricing — never invent figures. Match our consultative tone." Knowledge: product one-pagers, current price list, competitor battlecards, objection-handling doc. Help reps draft responses grounded in these.',
 'Reps get accurate, on-message answers to product, pricing, and objection questions drawn from approved material, so the whole team sells with one voice and no made-up numbers.'),
((select id from public.modules where slug='projects'), 'engineering',
 'New engineers keep writing code that ignores your conventions, and reviews get bogged down in style nits. You set up a Project loaded with your codebase standards and architecture docs.',
 E'Project custom instructions: "You help engineers on our platform team. Follow our conventions exactly." Knowledge to add: our style guide, the architecture overview, our API design doc, and an example service that models our patterns. When I ask for code, match these conventions and cite which doc a decision came from.',
 'Code Claude drafts already follows your naming, structure, and API patterns, cutting review churn and helping new hires ramp on your standards without memorizing every doc.'),
((select id from public.modules where slug='projects'), 'hr',
 'Employees ask the same policy questions and answers vary by who responds. You create a Project containing the employee handbook and policy docs so answers are consistent and grounded.',
 E'Set up an HR knowledge Project. Custom instructions: "Answer employee questions using only the uploaded policies. If something isn''t covered, say so and suggest who to contact — never guess." Knowledge: employee handbook, leave policy, expense policy, code of conduct. Draft clear, friendly answers I can send.',
 'You get consistent, policy-accurate answers to routine questions grounded in the real handbook, with an honest "not covered" instead of a guess — saving time and reducing risk.'),
((select id from public.modules where slug='projects'), 'finance',
 'Month-end questions about how to treat a cost or which account to use get answered from memory and sometimes wrongly. You build a Project holding your accounting policies and chart of accounts.',
 E'Create a finance Project. Custom instructions: "Answer using only our uploaded accounting policies and chart of accounts. Cite the policy section. If treatment is ambiguous, flag it for review rather than deciding." Knowledge: accounting policy manual, chart of accounts, revenue-recognition guide, close checklist.',
 'The team gets policy-grounded answers on account coding and treatment with citations, and genuinely ambiguous cases get flagged rather than guessed — keeping the books consistent.');

-- ---- artifacts ------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='artifacts'), 'recruitment',
 'You are running a hiring loop with four interviewers and need a shared scorecard so feedback is structured and comparable across candidates, not a scatter of Slack messages.',
 E'Build an interview scorecard as a document. Role: Product Designer. Columns: competency, interviewer notes, score 1-4. Rows for: portfolio depth, collaboration, systems thinking, communication, culture-add. Add a final recommendation section with hire / no-hire and a confidence field. Make it clean and printable.',
 'Claude produces an editable scorecard Artifact you refine live (add a column, reweight a competency) and export for every interviewer, so candidate feedback is consistent and easy to compare.'),
((select id from public.modules where slug='artifacts'), 'marketing',
 'You are pitching a campaign concept and want something more tangible than a slide — an interactive landing-page mockup the team can click through in the review.',
 E'Build a single-page landing page mockup for a campaign launching our eco-friendly water bottle. Include a hero with headline and CTA, a 3-feature row, a testimonial block, and an email-signup form. Use a fresh green palette. Make it a working HTML mockup I can click.',
 'Claude generates a live, clickable landing-page Artifact you iterate on by describing changes ("make the hero taller, swap the CTA copy"), giving stakeholders something real to react to in the meeting.'),
((select id from public.modules where slug='artifacts'), 'sales',
 'A prospect keeps asking whether your product pays for itself. You want to hand them an interactive ROI calculator they can plug their own numbers into, instead of a static PDF.',
 E'Build an interactive ROI calculator as a web app. Inputs: number of employees, hours saved per employee per week, average hourly cost. Output: monthly savings, annual savings, and payback period given our $2,000/month price. Make the inputs sliders, show results updating live, and keep the design clean and on-brand-neutral.',
 'Claude builds a working calculator Artifact the prospect can manipulate live — you tweak the formula or styling in seconds and share a tool that makes your value concrete instead of asserted.'),
((select id from public.modules where slug='artifacts'), 'engineering',
 'You want to prototype a UI component to settle a design debate quickly, without spinning up a branch and a dev server just to show what you mean.',
 E'Build a working React-style component as an interactive Artifact: a multi-select filter dropdown with search, select-all, and a count badge showing how many options are chosen. Include sample data of 12 items. Make it self-contained and functional so I can click through the interactions.',
 'Claude produces a runnable component Artifact you can interact with immediately and refine by describing behavior changes, letting you validate a UI idea in minutes instead of scaffolding a project.'),
((select id from public.modules where slug='artifacts'), 'hr',
 'A new engineer starts Monday and onboarding is scattered across emails. You want a single, clean onboarding checklist you can reuse for every new hire and hand to their manager.',
 E'Build a new-hire onboarding checklist as a document. Group tasks into: Before Day 1, Week 1, First 30 Days, First 90 Days. Include owner (HR / Manager / IT) and a checkbox for each item. Cover accounts, equipment, intro meetings, benefits enrollment, and a 30-day check-in. Make it reusable.',
 'Claude generates a structured, editable checklist Artifact you refine once and reuse for every hire, giving managers a clear, consistent onboarding plan they can actually follow.'),
((select id from public.modules where slug='artifacts'), 'finance',
 'You need to walk leadership through next year''s budget scenarios and want an interactive view of how changing a couple of assumptions moves the bottom line, not three static tabs.',
 E'Build an interactive budget dashboard as a web app. Inputs: revenue growth %, headcount added, marketing spend. Show projected annual revenue, total costs, and net margin updating live as I change inputs, plus a simple bar chart comparing three preset scenarios (conservative, base, aggressive). Keep it clean.',
 'Claude builds a live budget dashboard Artifact where leadership sees assumptions flow to the bottom line in real time — you adjust drivers and chart formatting on the fly during the review.');

-- ---- tool-use -------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='tool-use'), 'recruitment',
 'Before an intake call with a hiring manager, you need current market context: what this role pays now and what a target candidate''s company has been up to lately — facts too recent to know from memory.',
 E'Search the web for current salary benchmarks for a Senior DevOps Engineer in Berlin, and check for any recent news about [Company] — funding, layoffs, or reorgs — that would affect how their engineers feel about moving. Summarize with sources I can click.',
 'Using web search, Claude returns up-to-date pay ranges and fresh company news with links you can verify, so you walk into the intake and outreach informed instead of guessing.'),
((select id from public.modules where slug='tool-use'), 'marketing',
 'You are planning a campaign and need to know what competitors are doing right now and which messaging angles are trending this quarter — information that changes constantly.',
 E'Search the web for how our top 3 competitors are currently positioning their meal-kit brands — pull their latest taglines and any campaigns from the last few months. Then summarize 3 messaging gaps we could own. Include links to what you found.',
 'Claude searches live sources, summarizes current competitor positioning with citations, and proposes gaps to exploit — grounding your campaign strategy in what is happening now, not last year.'),
((select id from public.modules where slug='tool-use'), 'sales',
 'You have a big call in an hour and want the latest on the account — recent news, leadership changes, earnings — plus the notes from your last meeting pulled straight from your files.',
 E'Search the web for recent news on [Prospect Company] from the last 60 days — earnings, leadership changes, product launches. Then check my Google Drive for the file "Acme - discovery notes" and combine both into a one-page pre-call brief with three tailored talking points.',
 'Claude pulls current news via search and your prior notes via the Drive connector, then merges them into a pre-call brief — so you open the call current on the account and continuous with your history.'),
((select id from public.modules where slug='tool-use'), 'engineering',
 'You are reviewing an unfamiliar part of your codebase and want Claude to read the actual repository files and the relevant docs rather than reasoning from a pasted snippet.',
 E'Using the GitHub connector, look at the `payments` module in our repo. Read `charge.ts` and its tests, then explain how refunds are handled and flag any edge cases the tests don''t cover. Also search the web for the current Stripe refund API docs to confirm the behavior.',
 'Claude reads the real files through the connector and checks current API docs via search, giving you an analysis grounded in your actual code and today''s external behavior rather than assumptions.'),
((select id from public.modules where slug='tool-use'), 'hr',
 'A manager asks whether a specific leave situation is handled correctly, and you need both your internal policy and the current legal position, which may have changed recently.',
 E'Check my Drive for our "Parental Leave Policy" doc and summarize what it says about phased return. Then search the web for any recent changes to statutory parental leave entitlements in the UK for 2026, and flag where our policy might now be below the legal minimum. Cite sources.',
 'Claude reads your internal policy via the connector and checks current statutory rules via search, surfacing any gap between the two with sources — so your guidance is both on-policy and legally current.'),
((select id from public.modules where slug='tool-use'), 'finance',
 'You are updating a forecast and need current reference data — interest rates, FX, or a competitor''s latest reported numbers — that must be accurate as of today, not from training.',
 E'Search the web for the current Bank of England base rate and today''s GBP/USD rate, and find [Competitor]''s most recent quarterly revenue and operating margin from their latest filing. Summarize the figures in a table with source links so I can drop them into my forecast assumptions.',
 'Claude retrieves the latest rates and reported figures with citations and lays them out in a table, so your forecast assumptions rest on verifiable current data instead of stale numbers.');

-- ---- workflows ------------------------------------------------------------
insert into public.module_examples (module_id, profession, scenario, sample_prompt, outcome) values
((select id from public.modules where slug='workflows'), 'recruitment',
 'A new requisition just opened and you want to run your whole front end of hiring — job description, screening rubric, outreach, and an interview kit — as one repeatable chain instead of four separate scrambles.',
 E'Let''s build my hiring kit for a Senior Product Manager req, step by step. Step 1: draft the JD from these notes: [paste]. Once I approve, Step 2: a screening rubric with must-haves and nice-to-haves. Step 3: three outreach message variants. Step 4: a structured interview guide. We''ll refine each step before moving on.',
 'Each approved output feeds the next, so you finish with a complete, consistent hiring kit from one conversation — and you can reuse the same prompt chain for the next req.'),
((select id from public.modules where slug='workflows'), 'marketing',
 'You publish one flagship piece a week and then have to slice it into social, email, and ad copy. You want a content workflow that goes from brief to a full multi-channel package.',
 E'Let''s run my content workflow. Step 1: from this brief [paste], write a 900-word blog post in our voice. Step 2: cut it into 3 LinkedIn posts. Step 3: a subject line + short email promoting it. Step 4: two ad variations. Keep everything consistent with the blog''s angle. We''ll approve each step before the next.',
 'One brief becomes a coordinated, on-voice package across every channel in a single chain, turning a full afternoon of repurposing into a guided session you steer step by step.'),
((select id from public.modules where slug='workflows'), 'sales',
 'You want a repeatable prospecting motion: research the account, personalize the outreach, build a follow-up sequence, and produce clean CRM notes — the same way every time.',
 E'Run my prospecting workflow for [Prospect]. Step 1: search recent news on the account and summarize a hook. Step 2: write a personalized first email using that hook. Step 3: a 3-touch follow-up sequence. Step 4: a tidy CRM note capturing the research and plan. Approve each step as we go.',
 'Research, outreach, follow-ups, and CRM notes come out of one connected flow, giving you a personalized, well-documented sequence per prospect that you can run identically across your whole list.'),
((select id from public.modules where slug='workflows'), 'engineering',
 'A ticket lands and you want to move from problem to pull request in a structured way — clarify, design, implement, test, and write the PR description — rather than diving straight into code.',
 E'Let''s work this ticket end to end: [paste ticket]. Step 1: restate the requirement and list open questions. Step 2: propose a short design with trade-offs. Step 3: implement it in Go following our conventions. Step 4: write table-driven tests. Step 5: draft the PR description. We''ll review each stage.',
 'The ticket flows through clarify, design, code, test, and PR write-up as one chain, producing reviewable work at each stage and a clean PR — with your judgment steering every step.'),
((select id from public.modules where slug='workflows'), 'hr',
 'Onboarding a new hire touches accounts, paperwork, intros, and check-ins across weeks. You want to run the whole thing as one orchestrated workflow so nothing slips.',
 E'Help me run onboarding for a new marketing hire starting in two weeks. Step 1: build the full onboarding checklist by phase and owner. Step 2: draft the welcome email and their first-week schedule. Step 3: write a 30-day check-in agenda. Step 4: a manager briefing on how to support them. We''ll refine each piece.',
 'The full onboarding — checklist, comms, schedule, and check-ins — comes out of one connected flow, so every new hire gets a consistent, thorough start and the manager knows exactly what to do.'),
((select id from public.modules where slug='workflows'), 'finance',
 'Month-end close is a recurring grind: pulling numbers, reconciling, analyzing variances, and writing the summary. You want to chain it into a guided workflow you run the same way every month.',
 E'Let''s run month-end close. Step 1: from this trial balance [paste], flag accounts that moved more than 10% vs last month. Step 2: for each, draft a variance explanation to verify. Step 3: build the management summary with key highlights. Step 4: a short list of follow-up questions for department heads. Approve each step.',
 'Reconciliation flags, variance narratives, and the management summary flow from one chain, turning a scattered multi-day close into a repeatable guided process you refine and reuse each month.');

-- ===========================================================================
-- FLASHCARD DECKS  (one per module)
-- ===========================================================================
insert into public.flashcard_decks (module_id, title, order_index) values
((select id from public.modules where slug='chat-basics'), 'Meet Claude: Chat Basics — Key Concepts', 1),
((select id from public.modules where slug='prompting'),   'Prompting Fundamentals — Key Concepts', 2),
((select id from public.modules where slug='projects'),    'Projects & Persistent Context — Key Concepts', 3),
((select id from public.modules where slug='artifacts'),   'Artifacts: Build Real Things — Key Concepts', 4),
((select id from public.modules where slug='tool-use'),    'Tool Use & Connectors — Key Concepts', 5),
((select id from public.modules where slug='workflows'),   'Putting It Together: Real Workflows — Key Concepts', 6);

-- ===========================================================================
-- FLASHCARDS  (27 per module: 9 generic across 3 difficulty tiers + 3 per profession x 6)
-- ===========================================================================

-- ---- chat-basics ----
insert into public.flashcards (deck_id, profession, front, back, order_index, difficulty, card_type) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'What happens when you send a new message in an existing Claude chat?', 'Claude reads the entire conversation so far — your messages and its replies — before responding, so it can build directly on what came before.', 1, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'What is Claude''s "context window"?', 'The amount of conversation Claude can actively read and remember at once — everything within that window shapes its next reply.', 2, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'This is the term for starting a brand-new thread with Claude that has no memory of any other chat you''ve had.', 'The term is: **a new conversation** (fresh context).', 3, 'beginner', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'Why does it often work better to keep refining one request in the same chat rather than starting over each time?', 'Claude can see your earlier messages and its own prior answers, so follow-ups like "make it shorter" or "use a friendlier tone" land correctly without you having to re-explain the whole task.', 4, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'Claude''s first draft of your email is close but too formal — what''s the fastest way to fix it?', 'Reply in the same chat with a specific correction, like "make the tone warmer and more casual" — Claude will revise using the draft it already produced, rather than starting from scratch.', 5, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'This is what you should do when a conversation has drifted far from your original goal and keeps producing off-track answers.', 'The term is: **starting a new chat** (rather than fighting an over-long, tangled thread).', 6, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'Why can a very long-running chat start producing worse answers even though nothing about your questions changed?', 'As a conversation grows, older turns can fall outside the context window, or the thread accumulates conflicting instructions and dead-end tangents — both dilute what Claude can usefully draw on. A shorter, focused thread — or a fresh one with a clean summary — often performs better.', 7, 'advanced', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'You''ve been iterating on a strategy doc for an hour in one chat. Claude now contradicts something it said 30 messages ago and seems to have lost your key constraints.', 'This is a sign the thread has grown past what''s useful — summarize the decisions and constraints that still matter, start a new chat, and paste that summary in as the opening message so Claude starts from a clean, accurate footing.', 8, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'This describes the trade-off between continuing one long chat (rich shared context, but potential drift and dilution) versus starting fresh (clean slate, but you must manually re-supply context).', 'The term is: **conversation length trade-off** (context depth vs. context cleanliness).', 9, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'recruitment',
 'As a recruiter, what''s a simple first use of a Claude chat?', 'Ask Claude to draft a first-pass outreach message to a candidate, then refine it in the same thread until the tone and details feel right.', 10, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'recruitment',
 'You asked Claude to write a job description and it''s good but missing your company''s benefits section — what''s next?', 'Don''t start over — reply in the same chat with the missing details ("add a benefits section covering health, PTO, and remote flexibility") and Claude will fold it into the existing draft.', 11, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'recruitment',
 'You''re screening notes across 15 candidates in one long chat and Claude starts mixing up which notes belong to which candidate.', 'The thread has gotten too long and cluttered for Claude to track cleanly — split the work into one chat per candidate, or per batch, so each conversation''s context stays focused and accurate.', 12, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'marketing',
 'If Claude''s first draft of a social post isn''t quite your brand''s voice, what should you do?', 'Reply in the same chat and describe the voice you want ("more playful, shorter sentences") — Claude adjusts the existing draft instead of you rewriting it yourself.', 13, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'marketing',
 'This is the practice of sending a series of follow-up corrections in one chat — "punchier headline," "cut the jargon," "add a CTA" — instead of describing everything perfectly up front.', 'The term is: **iterating** (refining through conversation rather than a single perfect prompt).', 14, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'marketing',
 'You''ve been iterating on a campaign brief for 50+ messages and Claude just suggested an idea you already rejected earlier in the thread.', 'The chat has likely grown long enough that earlier turns are getting crowded out. Summarize the current direction and firm rejections in a short recap, and continue in a new chat so those decisions stay visible.', 15, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'sales',
 'What''s a good first message to send Claude when prepping for a sales call?', 'Give it the basics — who the prospect is, what they do, and what you want out of the call — so Claude has real context for the outline or talking points it drafts.', 16, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'sales',
 'Why should you keep asking follow-up questions in the same chat instead of re-describing your deal from scratch each time?', 'Claude already has the account context, objections, and prior drafts in that thread — follow-ups like "now write the follow-up email" reuse that context automatically, saving you retyping and keeping details consistent.', 17, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'sales',
 'This is what you should do before starting a new chat about a deal you''ve discussed at length before, so Claude isn''t starting cold.', 'The term is: **carrying context forward** (pasting a short recap of the deal stage, key objections, and next step into the new chat''s opening message).', 18, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'engineering',
 'You pasted an error message to Claude and got a fix — what should you do if it doesn''t work?', 'Reply in the same chat with what happened when you tried it — Claude will see the original error and its own suggestion, and can adjust rather than guess again from zero.', 19, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'engineering',
 'You''re debugging in one chat, and now want to ask about an unrelated formatting question for a different file.', 'Consider starting a second chat for the unrelated question — keeping topics separate avoids muddying the debugging thread''s context with unrelated details.', 20, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'engineering',
 'A long pair-programming chat has Claude proposing a fix that ignores a constraint you mentioned 60 messages ago.', 'That constraint has likely aged out of what''s easy for Claude to weigh — restate key constraints periodically in long technical threads, or start a fresh chat with a short spec summarizing them.', 21, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'hr',
 'What''s a low-risk first task for a new Claude chat if you work in HR?', 'Ask it to draft something routine, like a PTO policy FAQ answer or an onboarding checklist, then read it over and refine the wording together in the same chat.', 22, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'hr',
 'This is what''s happening when you tell Claude "keep everything the same but make section 2 more concise" and it edits only that part.', 'The term is: **targeted iteration** (giving a precise follow-up instruction so Claude revises just the part that needs it).', 23, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'hr',
 'You''re drafting a sensitive policy update across a long chat, and Claude''s latest version quietly drops a caveat you added earlier.', 'In long threads, earlier specific instructions can get crowded out. Re-state the caveat explicitly in your next message, and for anything sensitive, do a final full read-through rather than trusting incremental edits alone.', 24, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'finance',
 'You asked Claude to summarize a budget memo and want a shorter version — what do you do?', 'Just ask in the same chat — "make that three bullet points" — Claude will condense the summary it already gave you rather than needing the memo again.', 25, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'finance',
 'Why is it worth telling Claude your audience (e.g., "this is for the board" vs. "for my team") early in a chat?', 'That framing carries through the rest of the conversation — every later draft and follow-up will lean on it, so you don''t need to repeat the audience each time you ask for a revision.', 26, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'finance',
 'You''ve built up a detailed forecast discussion over many messages, and now need to share the key assumptions with a colleague who wasn''t in the chat.', 'Ask Claude, in that same thread, to summarize the finalized assumptions and decisions into a clean standalone recap — that turns a long working conversation into something shareable without you re-deriving it.', 27, 'advanced', 'scenario');

-- ---- prompting ----
insert into public.flashcards (deck_id, profession, front, back, order_index, difficulty, card_type) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'What makes a prompt "specific" rather than vague?', 'It states exactly what you want — the format, length, audience, and any constraints — instead of leaving Claude to guess your intent.', 1, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'What is a "role" prompt?', 'Asking Claude to respond as if it were a particular persona or expert (e.g., "as a patent attorney") so its tone, vocabulary, and focus match that perspective.', 2, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'This is the term for giving Claude one or more worked examples of the exact output you want, so it can match that pattern.', 'The term is: **few-shot prompting**.', 3, 'beginner', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'Why does adding context (audience, purpose, constraints) usually improve Claude''s first draft more than adding extra adjectives does?', 'Context narrows down what a "good" answer actually looks like for your situation, while adjectives like "great" or "professional" are subjective and don''t tell Claude what to prioritize.', 4, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'You ask Claude to "write a summary" and get something too long and generic — what''s missing from the prompt?', 'Specificity — state the target length, the audience, and what should be emphasized, so Claude knows what "good" means for this particular summary.', 5, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'This is the practice of telling Claude not just what to produce, but the exact structure or format it should follow.', 'The term is: **format instructions** (specifying output structure like bullet points, a table, or a fixed number of sections).', 6, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'When should you use few-shot examples instead of just describing what you want in words?', 'When the output has a specific style, structure, or nuance that''s hard to fully capture in a description — showing 1-3 examples of the exact pattern often communicates it faster and more reliably than explaining it.', 7, 'advanced', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'You''ve given Claude a detailed role, clear format instructions, and one example — but the output still misses the mark on tone.', 'Check whether your example itself actually demonstrates the tone you want — a mismatched or overly formal example can override written instructions, since Claude tends to weight concrete examples heavily.', 8, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'This describes combining a role, relevant context, and one or more examples in a single prompt, rather than relying on any one technique alone.', 'The term is: **layered prompting** (stacking specificity, role, and examples together for a more reliable result).', 9, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'recruitment',
 'What''s one simple way to make a job-description prompt more specific?', 'Name the exact role, seniority level, must-have skills, and where it will be posted — instead of just saying "write a job description for a developer."', 10, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'recruitment',
 'You ask Claude to "write outreach messages" for five different candidates and get near-identical generic notes.', 'Give Claude each candidate''s specific background and what drew you to their profile — specificity is what turns a form-letter feel into a message that reads as personalized.', 11, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'recruitment',
 'You want Claude to match your team''s exact interview-scorecard style, but describing the format in words keeps coming out slightly wrong.', 'Paste one completed scorecard as a few-shot example — showing the exact structure and level of detail communicates the format far more reliably than a written description.', 12, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'marketing',
 'What does it mean to give Claude a "role" when drafting marketing copy?', 'Asking it to write as a specific persona — e.g., "as a witty social media manager for a sneaker brand" — so the voice and priorities match that role.', 13, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'marketing',
 'This is what you''re doing when you paste three of your brand''s best-performing headlines before asking Claude to write new ones.', 'The term is: **few-shot prompting** (showing examples of the pattern you want repeated).', 14, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'marketing',
 'Claude''s ad copy is on-brand in tone but keeps missing your target audience''s actual pain points.', 'Tone alone isn''t enough context — add specifics about who the audience is and what problem they''re trying to solve, since audience context shapes content in a way persona alone can''t.', 15, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'sales',
 'Why is "write a follow-up email to a prospect" a weak prompt on its own?', 'It''s missing context — who the prospect is, what was discussed, and what action you want next — so Claude has to guess at the details that actually matter.', 16, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'sales',
 'How does telling Claude "respond as a sales coach reviewing this pitch" change its output?', 'It''s a role prompt — Claude shifts its focus toward critique, structure, and persuasiveness, the way an actual sales coach would, rather than just rewriting the pitch politely.', 17, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'sales',
 'You want objection-handling responses that match your team''s specific style — direct, but never pushy.', 'Give Claude two or three real examples of your team''s best objection responses as few-shot examples — that concrete pattern teaches the "direct but not pushy" balance more reliably than describing it abstractly.', 18, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'engineering',
 'What''s a simple way to make a code-request prompt more specific?', 'Name the language, the function''s exact inputs and outputs, and any constraints (e.g., no external libraries) rather than just describing the general goal.', 19, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'engineering',
 'You ask Claude to "review this code" and get generic praise with no real feedback.', 'Give it a role and focus — "as a senior reviewer, focus only on performance and edge cases" — narrowing the task produces sharper, more useful feedback than an open-ended request.', 20, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'engineering',
 'This is what you''re doing when you show Claude one function you''ve already written in your team''s exact style before asking it to write a second, similar one.', 'The term is: **few-shot prompting** (letting a concrete example carry style conventions words alone often miss).', 21, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'hr',
 'What makes "write a policy" a vague prompt?', 'It doesn''t say which policy, for what situation, or in what tone — Claude has to guess the context that actually determines what a good answer looks like.', 22, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'hr',
 'Why might asking Claude to "respond as an employee relations specialist" improve a tricky policy answer?', 'A role prompt shifts Claude''s focus toward the considerations that specialist would prioritize — fairness, tone, and compliance — rather than a generic informational answer.', 23, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'hr',
 'You need Claude to write several policy FAQ answers in your company''s exact voice, but a written description of that voice keeps falling short.', 'Paste two or three existing FAQ answers as examples — few-shot examples transmit voice and structure more precisely than adjectives like "friendly but professional" ever can.', 24, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'finance',
 'What''s missing from the prompt "summarize this report"?', 'Specificity — the audience, desired length, and what to emphasize (e.g., risks vs. opportunities) all shape what a useful summary looks like.', 25, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'finance',
 'This is what''s happening when you tell Claude "explain this like you''re briefing a first-time investor with no finance background."', 'The term is: **role prompting** (framing the audience/persona so Claude adjusts vocabulary and depth accordingly).', 26, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'finance',
 'You want Claude to produce variance-analysis commentary that matches the exact structure your finance team always uses.', 'Provide one completed example of the commentary format as a few-shot example — that concrete structure is far more reliable than describing "our usual format" in words.', 27, 'advanced', 'scenario');

-- ---- projects ----
insert into public.flashcards (deck_id, profession, front, back, order_index, difficulty, card_type) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'What is a Claude "Project"?', 'A dedicated space that holds custom instructions and reference knowledge shared across every chat inside it, so you don''t have to re-explain context each time.', 1, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'What are "custom instructions" in a Project?', 'Standing guidance you set once — like tone, format preferences, or house style — that Claude automatically applies to every conversation in that Project.', 2, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'This is the term for files or notes you add to a Project so Claude can reference them in every chat within it.', 'The term is: **project knowledge**.', 3, 'beginner', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'Why do Projects save time compared to individual chats for recurring work?', 'Instead of re-explaining your context, style, or reference material in every new chat, you set it up once in the Project and every conversation inside it automatically has access.', 4, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'You do the same type of weekly report every week, retyping the same background each time in a fresh chat.', 'Set up a Project with that background and formatting preferences as custom instructions and project knowledge — then each week you just start a new chat inside it and ask for the report.', 5, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'This is what happens when you update a Project''s knowledge files — every future chat in that Project automatically benefits, without you touching old chats.', 'The term is: **shared/persistent project context**.', 6, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'What''s the trade-off to watch for when you add a lot of reference material to a Project''s knowledge?', 'More material gives Claude more to draw on, but overly long or outdated project knowledge can crowd out what''s actually relevant to a given chat — keep it curated and current, not just comprehensive.', 7, 'advanced', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'A Project''s custom instructions say to always use a formal tone, but for one specific chat you need something more casual.', 'You can override standing instructions within a single chat by explicitly saying so — an in-chat request generally takes precedence over the Project''s default guidance for that conversation.', 8, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'This describes the risk of letting a Project''s knowledge base grow indefinitely without pruning outdated files.', 'The term is: **knowledge staleness** (old or conflicting reference material degrading the quality of answers).', 9, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'recruitment',
 'What might a recruiter add as project knowledge in a "Candidate Communications" Project?', 'Templates for outreach, past job descriptions, and the company''s tone-of-voice guide — so Claude can draw on them without you re-pasting each time.', 10, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'recruitment',
 'You keep re-explaining your company''s interview process to Claude in every new chat about candidate prep.', 'Move that explanation into a Project''s custom instructions once — every future chat in that Project will already know the process.', 11, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'recruitment',
 'Your "Hiring" Project''s knowledge includes an old job-leveling guide that was replaced last quarter.', 'Remove or update the outdated file — stale project knowledge can lead Claude to apply criteria that no longer reflect current hiring standards.', 12, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'marketing',
 'What''s a natural use of a Project for a marketing team?', 'A "Brand Voice" Project holding style guides, past campaigns, and messaging pillars, so every content request in that Project stays on-brand automatically.', 13, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'marketing',
 'This is what''s happening when a marketer uploads their brand guidelines once into a Project, instead of pasting them into every single content chat.', 'The term is: **project knowledge** (persistent reference material shared across the Project''s chats).', 14, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'marketing',
 'A "Campaigns" Project''s custom instructions default to a bold, energetic voice, but this week''s brief calls for a somber, empathetic tone.', 'State the override explicitly in that chat — an in-conversation instruction takes precedence over the Project''s standing tone default for that one chat.', 15, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'sales',
 'What could a sales rep store in a "Deal Prep" Project?', 'Product one-pagers, competitor comparisons, and objection-handling notes — so every deal-related chat can reference them automatically.', 16, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'sales',
 'Why is a Project better than one long ongoing chat for tracking multiple accounts?', 'A Project lets you start a clean chat per account while still sharing common reference material (like product info) across all of them — you get fresh context per deal without losing shared knowledge.', 17, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'sales',
 'Your "Enterprise Deals" Project knowledge still lists pricing from two quarters ago.', 'Update the pricing file — outdated project knowledge can quietly produce proposals or talking points based on numbers that are no longer accurate.', 18, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'engineering',
 'What might an engineer add to a Project''s knowledge for a specific codebase?', 'Architecture notes, coding conventions, or key API references — so Claude has that context in every chat about that codebase.', 19, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'engineering',
 'You keep pasting the same style guide into every new chat about your team''s codebase.', 'Add it once as project knowledge in a dedicated Project — every future chat inside it will already have that context available.', 20, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'engineering',
 'Your team''s Project knowledge still includes a deprecated API''s documentation alongside the current one.', 'Remove the deprecated docs — leaving both can cause Claude to mix guidance from the old and new APIs, producing subtly broken suggestions.', 21, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'hr',
 'What''s a good use of a Project for HR?', 'An "Employee Policies" Project holding the current handbook and FAQ answers, so policy questions get answered consistently across chats.', 22, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'hr',
 'This is what lets every chat inside an HR Project consistently reference the same up-to-date handbook, without re-uploading it each time.', 'The term is: **project knowledge** (shared reference files available to every chat in the Project).', 23, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'hr',
 'An "Onboarding" Project''s custom instructions specify a warm, welcoming tone by default, but you''re drafting a formal compliance notice this week.', 'Explicitly state the tone you need for that chat — an in-chat instruction overrides the Project''s default tone just for that conversation.', 24, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'finance',
 'What could a finance team store as project knowledge in a "Monthly Close" Project?', 'The chart of accounts, prior month templates, and reporting standards — so recurring close tasks don''t require re-explaining the setup each time.', 25, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'finance',
 'Why does using a Project help with consistency across multiple analysts on the same team?', 'Everyone''s chats inside the Project draw on the same custom instructions and knowledge files, so outputs stay aligned with shared standards instead of drifting based on who''s asking.', 26, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'finance',
 'Your "Forecasting" Project''s knowledge base has grown to include several superseded versions of the assumptions file.', 'Prune the outdated versions — a cluttered, conflicting knowledge base makes it harder for Claude to reliably pick the current, correct assumptions.', 27, 'advanced', 'scenario');

-- ---- artifacts ----
insert into public.flashcards (deck_id, profession, front, back, order_index, difficulty, card_type) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'What is an Artifact in Claude?', 'A separate editable pane where Claude puts substantial content it creates — like a document, code, or a visual — so you can view, edit, and iterate on it apart from the chat itself.', 1, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'What kinds of things can appear as Artifacts?', 'Documents, code snippets, websites, diagrams, and interactive apps — basically any sizeable, self-contained piece of content worth viewing and editing on its own.', 2, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'This is the term for asking Claude to revise something already showing in the side panel, rather than rewriting it from scratch in the chat.', 'The term is: **iterating on an Artifact**.', 3, 'beginner', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'Why are Artifacts useful for content you plan to keep revising?', 'They live in a separate, persistent view you can keep referring back to and editing directly, instead of scrolling through chat messages to find the latest version buried in the conversation.', 4, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'You asked Claude to build a simple interactive calculator and it appeared in a side panel you can click and test.', 'That''s an Artifact — because it''s a real, self-contained interactive piece of content, Claude renders it separately so you can actually use it, not just read about it.', 5, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'This is what you''re doing when you tell Claude "change the header color to blue" about the app currently shown in the side panel.', 'The term is: **iterating on an Artifact** (a targeted edit to existing generated content).', 6, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'Why might you deliberately ask Claude to make something an Artifact rather than just describe it in chat?', 'When the deliverable is meant to be reused, shared, viewed as a finished thing, or interacted with (like a working app or a polished document), an Artifact gives you a clean, standalone version — separate from the back-and-forth conversation that produced it.', 7, 'advanced', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'You''ve been iterating on a dashboard Artifact for many rounds, and now want a totally different visual style rather than a tweak.', 'For a major change, it''s often cleaner to describe the new direction clearly and let Claude regenerate significant portions, rather than nudging incrementally — small iterative edits are best for refinements, not overhauls.', 8, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'This describes the judgment call between making a small targeted edit request versus asking for a substantial regeneration of an Artifact.', 'The term is: **iteration scope** (deciding whether a change warrants a tweak or a rebuild).', 9, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'recruitment',
 'What''s a good use of an Artifact for a recruiter?', 'A polished candidate scorecard template or a formatted job posting — content substantial and reusable enough to be worth its own editable view.', 10, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'recruitment',
 'You want to tweak the layout of a candidate comparison table Claude generated as an Artifact.', 'Ask Claude directly to adjust that Artifact — e.g., "add a column for years of experience" — and it will update the existing table rather than starting a new one.', 11, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'recruitment',
 'You''ve iterated many small tweaks into a hiring dashboard Artifact, and now want to switch it from a table layout to a visual card layout entirely.', 'That''s a big enough shift to ask for a rebuild — describe the new card-based design clearly and let Claude regenerate the Artifact, rather than nudging the table incrementally toward something it was never built to be.', 12, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'marketing',
 'What kind of marketing content is a good fit for an Artifact?', 'A landing page mockup, a formatted content calendar, or a one-page campaign brief — substantial content worth viewing and editing on its own.', 13, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'marketing',
 'This is what''s happening when you ask Claude to "make the CTA button bigger" on the landing page currently shown in the side panel.', 'The term is: **iterating on an Artifact**.', 14, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'marketing',
 'A campaign one-pager Artifact has gone through a dozen small edits and no longer matches the clean structure you originally wanted.', 'Rather than one more small nudge, describe the structure you actually want now and ask Claude to regenerate the one-pager — many small edits can compound into something messier than a clean rebuild.', 15, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'sales',
 'What''s a natural Artifact for a sales rep to request?', 'A formatted proposal document or a pricing comparison table — content meant to be reviewed, edited, and eventually shared as a finished piece.', 16, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'sales',
 'You''re refining a proposal Artifact and need one section reworded without touching the rest.', 'Ask specifically for that section — "reword the executive summary, keep everything else" — Claude edits just that part of the existing Artifact.', 17, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'sales',
 'Your proposal Artifact has been tweaked so many times through small requests that its structure has become inconsistent.', 'Describe the ideal structure clearly and ask for a fresh version — a full regeneration often produces a cleaner result than continuing to patch an Artifact that''s drifted through many incremental edits.', 18, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'engineering',
 'Why would Claude put a piece of code in an Artifact instead of just showing it in chat?', 'Substantial or runnable code is typically rendered as an Artifact so you can view, edit, and (for supported types) interact with it directly, separate from the conversation.', 19, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'engineering',
 'Claude built a small interactive tool as an Artifact and you want to add one more input field.', 'Ask for that specific change in the chat — "add a field for the discount percentage" — and Claude updates the existing Artifact''s code rather than rebuilding everything from scratch.', 20, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'engineering',
 'An Artifact-based prototype has grown through many incremental feature requests and its structure is getting tangled.', 'That''s a sign it''s time for a larger regeneration rather than another patch — describe the cleaned-up structure you want and let Claude rebuild it, since incremental patches on a tangled base tend to compound the mess.', 21, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'hr',
 'What HR content is a good fit for an Artifact?', 'A formatted onboarding checklist or a polished policy handout — content substantial enough to be worth its own editable, reusable view.', 22, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'hr',
 'This is what''s happening when you ask Claude to "shorten the PTO section" on the handbook currently open in the side panel.', 'The term is: **iterating on an Artifact**.', 23, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'hr',
 'An onboarding checklist Artifact has been edited piecemeal so many times that sections now overlap and repeat.', 'Ask Claude to regenerate the checklist from a clear, current outline rather than trimming it again — a rebuild avoids carrying forward the redundancy that small edits accumulated.', 24, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'finance',
 'What''s a good use of an Artifact for finance work?', 'A formatted budget summary or a variance-analysis table — substantial, structured content worth its own editable view outside the chat.', 25, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'finance',
 'You want to update just the Q3 numbers in a forecast table Artifact, leaving everything else untouched.', 'Ask specifically for that update — "update only the Q3 column with these figures" — Claude edits just that part of the existing table.', 26, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'finance',
 'A budget Artifact has accumulated many small structural tweaks over weeks and no longer matches your reporting standard cleanly.', 'Rather than another incremental fix, describe the standard structure you need and ask Claude to regenerate the table — a clean rebuild avoids compounding small inconsistencies from prior edits.', 27, 'advanced', 'scenario');

-- ---- tool-use ----
insert into public.flashcards (deck_id, profession, front, back, order_index, difficulty, card_type) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'What does it mean for Claude to "use a tool"?', 'Claude can call on external capabilities beyond its own knowledge — like searching the web or pulling data from a connected app — to help answer your request, then use those results in its reply.', 1, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'What is web search used for in a Claude conversation?', 'It lets Claude look up current information beyond its training data — useful for recent events, live data, or anything that might have changed since it was trained.', 2, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'This is the term for a pre-built integration that lets Claude read from or act on a specific external app, like a calendar or a docs tool.', 'The term is: **connector**.', 3, 'beginner', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'Why might Claude decide to search the web instead of just answering from what it already knows?', 'If a question depends on current, time-sensitive, or very specific information — like today''s stock price or a recent product release — Claude''s training data alone may be outdated or incomplete, so a live search fills that gap.', 4, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'You ask Claude about a competitor''s product update that launched this week.', 'This is a good case for web search — Claude''s training data has a cutoff, so recent events need a live lookup to be accurate.', 5, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'This is the open standard that lets Claude connect to external tools and data sources in a consistent, extensible way.', 'The term is: **MCP (Model Context Protocol)**.', 6, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'Why is it worth checking the source Claude cites after a web search, rather than trusting the summary alone?', 'Search results can vary in reliability, be outdated despite being "live," or be summarized imprecisely — for anything decision-critical, verifying the underlying source protects you from acting on a subtly wrong synthesis.', 7, 'advanced', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'You''ve connected Claude to your team''s project-management tool, and it now pulls in task data automatically for status updates.', 'Because a connector gives Claude read (and sometimes write) access to real data, review what it''s pulling in and what actions it''s taking carefully — an incorrect assumption acted on through a connector affects real systems, not just a chat reply.', 8, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'This describes the general judgment needed when giving Claude tool or connector access: weighing the convenience of automated actions against the risk of it acting on incomplete or misread information.', 'The term is: **tool-use oversight** (staying in the loop on what tools are doing on your behalf).', 9, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'recruitment',
 'How might web search help a recruiter using Claude?', 'It can look up current salary benchmarks or recent company news about a candidate''s background — information beyond what Claude already knows from training.', 10, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'recruitment',
 'You want Claude to check a candidate''s public professional presence as part of prep for an interview.', 'Web search can pull recent, current information for this kind of lookup, since a candidate''s public profile can change frequently and Claude''s training data may be out of date.', 11, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'recruitment',
 'A calendar connector now lets Claude auto-schedule interviews based on availability it reads directly.', 'Because this connector can take real scheduling actions, double-check the first several bookings it makes closely — a misread availability slot creates a real calendar conflict, not just a wrong chat answer.', 12, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'marketing',
 'Why might a marketer use web search inside a Claude chat?', 'To pull in current trends, competitor campaigns, or recent news relevant to a piece of content — things beyond Claude''s training cutoff.', 13, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'marketing',
 'This is the term for connecting Claude to your team''s analytics or content-management tool so it can read real campaign data directly.', 'The term is: **connector**.', 14, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'marketing',
 'Claude searched the web for a competitor''s latest pricing and summarized it, but the number seems oddly specific.', 'Check the original source before using that number in a strategy document — a summarized search result can occasionally be imprecise, and decision-critical numbers deserve direct verification.', 15, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'sales',
 'How could web search help a sales rep prep for a call?', 'It can pull recent news about the prospect''s company — funding rounds, leadership changes, or product launches — that Claude wouldn''t know from training alone.', 16, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'sales',
 'You want Claude to pull the latest deal stage and notes directly from your CRM before drafting a follow-up.', 'This is a good use for a connector — linking Claude to your CRM lets it read real, current deal data instead of you manually copying it in.', 17, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'sales',
 'A CRM connector now lets Claude update deal stages automatically based on your conversation notes.', 'Because this connector writes real data back into your CRM, review its updates before trusting them fully — an inaccurate note-to-stage mapping quietly corrupts your actual pipeline, not just a chat summary.', 18, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'engineering',
 'Why might an engineer use web search inside a Claude chat?', 'To look up current documentation for a library, a recent CVE, or a framework update released after Claude''s training cutoff.', 19, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'engineering',
 'This is the open standard that lets Claude connect consistently to developer tools like a codebase, issue tracker, or internal API.', 'The term is: **MCP (Model Context Protocol)**.', 20, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'engineering',
 'You''ve connected Claude to your team''s issue tracker via MCP, and it now proposes closing tickets based on its read of recent commits.', 'Review its proposed actions before it closes anything — a connector acting on a misread commit history can close a real ticket incorrectly, which is a different kind of mistake than just a wrong chat answer.', 21, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'hr',
 'How might web search help someone working in HR?', 'It can look up current employment law changes or benchmark benefits data — information that shifts over time and may be newer than Claude''s training data.', 22, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'hr',
 'Why would connecting Claude to your HRIS (HR information system) via a connector be useful?', 'It lets Claude read real, current employee data directly — like headcount or leave balances — instead of you manually exporting and pasting reports each time.', 23, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'hr',
 'An HRIS connector now lets Claude draft communications referencing specific employees'' leave balances it reads directly.', 'Because this touches sensitive personal data pulled automatically, review what''s being read and shared carefully — an incorrect or overly broad data pull through a connector is a real privacy risk, not just a wrong answer.', 24, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'finance',
 'How might web search help someone doing finance work with Claude?', 'It can look up a current exchange rate or a recent market move — live data that changes constantly and wouldn''t be current in Claude''s training.', 25, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'finance',
 'You want Claude to pull the latest numbers directly from your accounting software instead of you exporting a report each time.', 'This is a good use for a connector — it lets Claude read current data directly from the source instead of relying on a manually pasted, possibly stale export.', 26, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'finance',
 'A connector now lets Claude pull live figures from your accounting system directly into a forecast draft.', 'Because forecasts inform real decisions, spot-check the pulled figures against the source before trusting the draft fully — a connector reading the wrong period or account can silently skew numbers that look correct at a glance.', 27, 'advanced', 'scenario');

-- ---- workflows ----
insert into public.flashcards (deck_id, profession, front, back, order_index, difficulty, card_type) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'What is a "workflow" when working with Claude?', 'A sequence of connected steps — often several prompts in a row — that together accomplish a larger task, rather than relying on a single one-shot request.', 1, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'Why break a big task into multiple smaller steps for Claude instead of one giant prompt?', 'Smaller steps are easier to check and correct along the way — you can catch a problem early rather than discovering it buried inside one huge, complex output.', 2, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'This is the term for a workflow you''ve refined once and can reuse for the same type of task going forward.', 'The term is: **a repeatable prompt chain**.', 3, 'beginner', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'What''s the benefit of reviewing Claude''s output at each step of a multi-step workflow, rather than only at the very end?', 'Catching an issue early means it doesn''t compound into every step that builds on it — a mistake at step one silently affects steps two through five if it goes unnoticed until the final result.', 4, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'You need Claude to research a topic, draft an outline, then write a full report — all connected pieces of one bigger task.', 'Treat this as a workflow — do the research step first, confirm it looks right, then explicitly ask for the outline based on that research, then the draft — checking in between each step rather than asking for everything at once.', 5, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'This is what you''re doing when you save the sequence of prompts that worked well for a recurring task, so you can reuse it next time with new details swapped in.', 'The term is: **building a repeatable workflow**.', 6, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'How should you decide where to draw the boundaries between steps in a multi-step workflow?', 'Split at points where you''d actually want to review or could plausibly want to redirect the work — if a step''s output feeds directly and reliably into the next with no real decision point, it''s often fine to combine them — splitting everywhere adds friction without adding safety.', 7, 'advanced', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'A workflow you built for one recurring report works well, but a slightly different report needs a modified version of two of the five steps.', 'Rather than building an entirely new workflow, adapt the existing one — reuse the three steps that transfer directly and only rework the two that need to change, since most of the sequence''s value carries over.', 8, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'This describes combining several Claude capabilities in sequence — like research via web search, then drafting, then a formatted Artifact — into one coherent multi-step process.', 'The term is: **an end-to-end workflow**.', 9, 'advanced', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'recruitment',
 'What might a recruitment workflow with Claude look like end-to-end?', 'Draft the job posting, then generate outreach messages, then create interview questions — three connected steps that build a complete hiring kit rather than one big request.', 10, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'recruitment',
 'You need to screen resumes, then draft personalized outreach for the strong ones, then prep interview questions for whoever responds.', 'Run this as a workflow — screen first and review the shortlist, then draft outreach for just that shortlist, then prep questions only once interviews are actually scheduled, checking in between each stage.', 11, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'recruitment',
 'Your resume-screening-to-outreach workflow works well, but a new role needs different screening criteria and a different outreach tone.', 'Reuse the overall structure but swap in the new criteria at the screening step and the new tone at the outreach step — the workflow''s shape still holds even though two of its steps need real changes.', 12, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'marketing',
 'What could a content-creation workflow with Claude include end-to-end?', 'Research the topic, draft an outline, write the full post, then adapt it into social captions — a chain of connected steps rather than one giant prompt.', 13, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'marketing',
 'Why check the outline before asking Claude to write the full blog post from it?', 'If the outline''s structure or angle is off, catching it early saves you from a full draft built on the wrong foundation — reviewing at each step avoids the mistake compounding.', 14, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'marketing',
 'Your blog-post workflow (research, outline, draft, social recap) works well, but this campaign needs a video script instead of a blog post at the drafting step.', 'Keep the research and outline steps as-is, and swap only the drafting step''s output format — most of the workflow''s value is in the earlier steps, which don''t need to change just because the final format does.', 15, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'sales',
 'What could a deal-prep workflow with Claude look like end-to-end?', 'Research the prospect, draft talking points, then prepare a follow-up email template — connected steps building toward a full call-ready package.', 16, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'sales',
 'You want Claude to research a prospect, then draft a personalized pitch, then create objection-handling notes — one after another.', 'Treat it as a workflow — confirm the research looks accurate first, since the pitch and objection notes both build on it, and an error there would carry through the rest.', 17, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'sales',
 'Your outreach workflow (research, pitch draft, follow-up email) works for cold prospects, but warm referrals need a different opening in the pitch step.', 'Keep the research and follow-up steps unchanged, and only adjust the pitch step''s opening for referral context — most of the sequence transfers directly.', 18, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'engineering',
 'What could a code-review workflow with Claude include end-to-end?', 'Summarize the diff, flag potential issues, then draft review comments — a chain of steps rather than one request to "review this."', 19, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'engineering',
 'This is what you''re doing when you check that Claude''s bug diagnosis is correct before asking it to draft the actual fix.', 'The term is: **reviewing at each step** (catching an issue before it compounds into the next step).', 20, 'intermediate', 'reverse'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'engineering',
 'Your bug-triage workflow (reproduce, diagnose, draft fix) works well for backend bugs, but frontend bugs need a different reproduction step.', 'Reuse the diagnose and draft-fix steps as-is, and only rework the reproduction step for frontend specifics — the overall shape of the workflow still holds.', 21, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'hr',
 'What could an onboarding-content workflow with Claude look like end-to-end?', 'Draft the welcome email, then the first-week checklist, then FAQ answers — a sequence of connected pieces rather than one massive request.', 22, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'hr',
 'Why review the welcome email''s tone before asking Claude to extend that same tone across the whole onboarding checklist?', 'If the tone is off in the first piece, catching it there prevents that same issue from repeating across every subsequent document in the sequence.', 23, 'intermediate', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'hr',
 'Your onboarding workflow (welcome email, checklist, FAQ) works well, but a new remote-hire track needs a different checklist step.', 'Keep the welcome email and FAQ steps as they are, and rework only the checklist step for remote-specific logistics — most of the workflow still applies.', 24, 'advanced', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'finance',
 'What could a monthly reporting workflow with Claude include end-to-end?', 'Summarize the raw numbers, draft the variance commentary, then format the executive summary — connected steps building toward the finished report.', 25, 'beginner', 'concept'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'finance',
 'You want Claude to summarize this month''s figures, then explain the variances, then write an executive summary — one after another.', 'Treat it as a workflow and check the number summary for accuracy first — the variance commentary and executive summary both depend on it, so an early error would carry through the rest.', 26, 'intermediate', 'scenario'),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'finance',
 'Your close-reporting workflow (summarize, variance commentary, exec summary) works well, but the board version needs a different exec-summary step.', 'Keep the summarize and variance-commentary steps unchanged, and adapt only the exec-summary step''s tone and depth for the board audience — most of the workflow transfers directly.', 27, 'advanced', 'scenario');

-- ===========================================================================
-- QUIZ QUESTIONS  (27 per module: 9 generic across 3 difficulty tiers + 3 per profession x 6)
-- ===========================================================================

-- ---- chat-basics ----
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, difficulty, kind, hint, order_index) values
((select id from public.modules where slug='chat-basics'), null,
 'In a Claude conversation, what does Claude use to generate each new reply?',
 '["The full message history in that conversation", "Only your most recent message", "A saved profile of your preferences", "The title you gave the chat"]'::jsonb,
 0, 'Claude reads the whole conversation so far — not just your latest message — to generate a reply that fits the context.',
 'beginner', 'mcq', 'Think about how much of the conversation Claude actually re-reads each turn.', 1),
((select id from public.modules where slug='chat-basics'), null,
 'Starting a new chat with Claude gives you a completely fresh conversation with no memory of your other chats.',
 '["True", "False"]'::jsonb,
 0, 'Each new chat begins with a clean slate — Claude has no access to other conversations unless you paste that information in.',
 'beginner', 'true_false', 'Consider whether separate chats are linked to one another.', 2),
((select id from public.modules where slug='chat-basics'), null,
 'You ask Claude to write a short bio, then reply "make it more casual" in the same chat — what happens?',
 '["Claude revises the bio it already wrote, using the casual-tone feedback", "Claude asks you to repaste the original bio", "Claude ignores the request since it''s a new topic", "Claude starts an entirely unrelated new bio"]'::jsonb,
 0, 'Because the follow-up is in the same conversation, Claude can see the earlier draft and revise it directly.',
 'beginner', 'scenario', 'Remember that everything earlier in the same chat is still visible to Claude.', 3),
((select id from public.modules where slug='chat-basics'), null,
 'The running history of messages that Claude reads before generating each reply is called the _____.',
 '["context window", "chat title", "system log", "memory bank"]'::jsonb,
 0, '"Context window" is the term for the conversation history Claude actively reads and reasons over.',
 'intermediate', 'fill_blank', 'This is the same idea as "how far back Claude can see."', 4),
((select id from public.modules where slug='chat-basics'), null,
 'Why is it often better to correct a draft with a follow-up message than to retype the whole request?',
 '["The follow-up builds on the existing draft and context, so Claude can make a targeted edit", "Claude charges less for follow-up messages", "Retyping the request deletes the chat", "Follow-ups always produce a completely different answer"]'::jsonb,
 0, 'A follow-up message lets Claude reuse everything already established in the chat, so it can make a precise, targeted change.',
 'intermediate', 'mcq', 'Think about what Claude can still see when you send a short correction.', 5),
((select id from public.modules where slug='chat-basics'), null,
 'If you want Claude to remember details from a conversation you had yesterday in a different chat, it will automatically recall them in today''s new chat.',
 '["True", "False"]'::jsonb,
 1, 'Conversations don''t share memory by default — you''d need to paste in the relevant details yourself.',
 'intermediate', 'true_false', 'Ask whether chats are connected behind the scenes.', 6),
((select id from public.modules where slug='chat-basics'), null,
 'After 80 messages debating a marketing plan, Claude suggests an option the team explicitly ruled out 50 messages earlier. What''s the most likely cause, and best fix?',
 '["The thread has grown long enough that earlier turns are getting crowded out \u2014 summarize the decisions and start fresh", "Claude is deliberately testing the team''s patience", "The chat has a bug and needs to be deleted", "Claude cannot ever forget anything, so this must be a misunderstanding"]'::jsonb,
 0, 'Very long threads can dilute or push out earlier context. Recapping key decisions in a fresh chat restores a clean, reliable footing.',
 'advanced', 'scenario', 'Think about what happens to older turns once a conversation grows very large.', 7),
((select id from public.modules where slug='chat-basics'), null,
 'When a chat has drifted off-track after many messages, the most reliable fix is often to write a short _____ of what''s been decided and start a new conversation.',
 '["summary", "apology", "transcript", "attachment"]'::jsonb,
 0, 'A concise summary of decisions and constraints gives the new chat clean, accurate context to work from.',
 'advanced', 'fill_blank', 'Think about what you''d hand someone joining the project midway.', 8),
((select id from public.modules where slug='chat-basics'), null,
 'What''s the real trade-off between continuing one very long chat versus starting a new one?',
 '["Long chats keep rich shared context but risk drift and dilution \u2014 new chats are clean but need context rebuilt manually", "Long chats are always worse and should never be used", "New chats automatically inherit all prior context, so there''s no trade-off", "Chat length has no effect on answer quality"]'::jsonb,
 0, 'Both approaches have real costs — a long thread can lose sharpness, while a new one starts blank — so the right choice depends on the situation.',
 'advanced', 'mcq', 'Weigh what you keep and what you lose in each approach.', 9),
((select id from public.modules where slug='chat-basics'), 'recruitment',
 'You''re using Claude to write a candidate outreach message. What''s the best first step?',
 '["Give Claude the role, candidate background, and tone you want, then refine in follow-ups", "Ask Claude to guess everything without any details", "Only tell Claude the company name", "Send the message before reviewing it"]'::jsonb,
 0, 'Starting with real specifics gives Claude something concrete to work from, and you can refine from there.',
 'beginner', 'mcq', 'Think about what makes a first draft useful versus generic.', 10),
((select id from public.modules where slug='chat-basics'), 'recruitment',
 'A recruiter asks Claude for a job description, then in the same chat says "add a benefits section." What does Claude do?',
 '["Adds the benefits section to the existing draft, since it can see the conversation so far", "Writes a brand-new job description from scratch", "Asks the recruiter to repaste the whole draft", "Ignores the request since it''s unrelated to hiring"]'::jsonb,
 0, 'Because it''s the same chat, Claude edits the draft it already produced rather than starting over.',
 'intermediate', 'scenario', 'Consider what Claude can still see from earlier in this thread.', 11),
((select id from public.modules where slug='chat-basics'), 'recruitment',
 'When screening many candidates in one long Claude chat, keeping everyone''s notes in a single thread is always the most reliable approach.',
 '["True", "False"]'::jsonb,
 1, 'Very long threads with many candidates can blur together — splitting into separate chats per candidate or batch keeps context accurate.',
 'advanced', 'true_false', 'Think about what happens to accuracy as a single thread gets crowded with many similar cases.', 12),
((select id from public.modules where slug='chat-basics'), 'marketing',
 'If Claude''s first draft of a social post isn''t in your brand voice, the fastest fix is to reply in the same chat and describe the _____ you want.',
 '["tone", "font", "hashtag count", "file format"]'::jsonb,
 0, 'Describing the tone you want lets Claude revise the existing draft directly.',
 'beginner', 'fill_blank', 'Think about what aspect of writing style you''d actually be correcting.', 13),
((select id from public.modules where slug='chat-basics'), 'marketing',
 'Why does sending several small follow-up corrections often work better than trying to write one perfect prompt for a campaign brief?',
 '["Each correction builds on the previous draft and context Claude already has", "Claude gives better answers only after the tenth message", "Follow-ups reset the conversation, giving a cleaner result", "Perfect prompts are impossible to write for marketing tasks"]'::jsonb,
 0, 'Iterating lets you refine gradually, and Claude uses everything already established in the thread.',
 'intermediate', 'mcq', 'Think about what a follow-up message can build on that a brand-new prompt can''t.', 14),
((select id from public.modules where slug='chat-basics'), 'marketing',
 'Fifty messages into a campaign brainstorm, Claude re-suggests an idea the team rejected early on. What should the marketer do?',
 '["Summarize the current direction and firm rejections, then continue in a new chat", "Keep repeating the rejection in every message forever", "Assume Claude is malfunctioning and stop using it", "Delete the chat with no summary and start blind"]'::jsonb,
 0, 'A clean recap in a new chat restores the important decisions without the clutter of a long thread.',
 'advanced', 'scenario', 'Think about what carries forward reliably versus what tends to get buried in a long thread.', 15),
((select id from public.modules where slug='chat-basics'), 'sales',
 'What should you give Claude before asking it to draft sales call talking points?',
 '["Who the prospect is, what they do, and your goal for the call", "Nothing \u2014 Claude works best with no context", "Only the prospect''s name", "The entire company''s annual report"]'::jsonb,
 0, 'Concrete, relevant context lets Claude produce talking points that actually fit the call.',
 'beginner', 'mcq', 'Think about what information turns a generic outline into a useful one.', 16),
((select id from public.modules where slug='chat-basics'), 'sales',
 'Once you''ve discussed a deal at length in one chat, asking Claude to "now draft the follow-up email" will reuse the context already in that conversation.',
 '["True", "False"]'::jsonb,
 0, 'Because it''s the same chat, Claude can pull from everything already discussed about the deal.',
 'intermediate', 'true_false', 'Consider what''s still visible to Claude within a single ongoing conversation.', 17),
((select id from public.modules where slug='chat-basics'), 'sales',
 'You want to start a new chat about a deal you discussed extensively last week. What''s the best way to avoid Claude starting cold?',
 '["Paste a short recap of the deal stage, key objections, and next step as your opening message", "Assume Claude remembers last week''s chat automatically", "Re-explain the entire company history in exhaustive detail", "Avoid giving any context so Claude isn''t biased"]'::jsonb,
 0, 'A concise recap gives the new chat the essential context without dragging in an old, possibly cluttered thread.',
 'advanced', 'scenario', 'Think about what a colleague would need to get up to speed quickly.', 18),
((select id from public.modules where slug='chat-basics'), 'engineering',
 'You tried a fix Claude suggested and it didn''t work. What''s the best next step?',
 '["Reply in the same chat describing what happened when you tried it", "Start a brand-new chat with no context", "Assume the bug is unfixable", "Ask an unrelated question instead"]'::jsonb,
 0, 'Replying in the same thread lets Claude see the original error and its own suggestion, so it can adjust.',
 'beginner', 'mcq', 'Think about what information helps Claude improve its next attempt.', 19),
((select id from public.modules where slug='chat-basics'), 'engineering',
 'Starting a separate chat for an unrelated formatting question, instead of adding it to your debugging thread, helps keep each conversation''s _____ focused.',
 '["context", "file size", "font", "username"]'::jsonb,
 0, 'Keeping unrelated topics in separate chats avoids diluting each thread''s context with irrelevant details.',
 'intermediate', 'fill_blank', 'Think about what gets muddied when unrelated topics share one conversation.', 20),
((select id from public.modules where slug='chat-basics'), 'engineering',
 'In a 60-message pair-programming chat, Claude proposes a fix that ignores a constraint you mentioned early on. What''s the best move?',
 '["Restate the key constraint, or start a fresh chat with a short spec summarizing the constraints", "Give up on using Claude for this task", "Assume the constraint no longer matters", "Keep repeating the same full request from scratch each time"]'::jsonb,
 0, 'Long threads can crowd out earlier specifics — restating constraints, or resetting with a clean summary, keeps them front and center.',
 'advanced', 'scenario', 'Think about how easy it is for a detail to get buried after dozens of messages.', 21),
((select id from public.modules where slug='chat-basics'), 'hr',
 'What''s a good low-risk first task for a new Claude chat in HR work?',
 '["Drafting something routine, like an onboarding checklist, then refining it together", "Immediately finalizing a sensitive termination letter with no review", "Asking Claude to make final legal decisions", "Skipping review of anything Claude drafts"]'::jsonb,
 0, 'Routine, low-stakes drafts are a great way to get comfortable iterating with Claude before tackling sensitive material.',
 'beginner', 'mcq', 'Think about what kind of task is safe to practice on.', 22),
((select id from public.modules where slug='chat-basics'), 'hr',
 'Telling Claude "keep everything the same but make section 2 more concise" will cause it to rewrite the entire document from scratch.',
 '["True", "False"]'::jsonb,
 1, 'A precise, targeted instruction lets Claude revise just the part you asked about, not the whole document.',
 'intermediate', 'true_false', 'Think about what a specific instruction lets Claude leave untouched.', 23),
((select id from public.modules where slug='chat-basics'), 'hr',
 'While drafting a sensitive policy update across a long chat, Claude''s latest version quietly drops a caveat you added earlier. What should you do?',
 '["Re-state the caveat explicitly and do a full read-through before finalizing anything sensitive", "Trust the latest version completely without checking", "Assume Claude removed it intentionally for a good reason", "Abandon the chat and never mention the caveat again"]'::jsonb,
 0, 'Long threads can lose track of earlier specific instructions, so sensitive material deserves a careful final review.',
 'advanced', 'scenario', 'Think about what''s easy to lose track of in a long, evolving draft.', 24),
((select id from public.modules where slug='chat-basics'), 'finance',
 'You asked Claude to summarize a budget memo and want it shorter. What should you do?',
 '["Ask in the same chat for a shorter version \u2014 Claude will condense what it already wrote", "Paste the entire memo again from scratch", "Open a new chat with no context", "Give up, since summaries can''t be revised"]'::jsonb,
 0, 'Claude can see its own earlier summary in the thread and shorten it directly.',
 'beginner', 'mcq', 'Think about what Claude still has access to from earlier in the conversation.', 25),
((select id from public.modules where slug='chat-basics'), 'finance',
 'Telling Claude your audience early in a chat (e.g., "this is for the board") is useful because that framing _____ through the rest of the conversation.',
 '["carries", "disappears", "conflicts", "resets"]'::jsonb,
 0, 'Once established, that context applies to later drafts and revisions without needing to be repeated.',
 'intermediate', 'fill_blank', 'Think about whether early details stay relevant as the chat continues.', 26),
((select id from public.modules where slug='chat-basics'), 'finance',
 'You''ve built a detailed forecast discussion over many messages and need to share the key assumptions with a colleague who wasn''t in the chat. What''s the best move?',
 '["Ask Claude, in that same thread, to summarize the finalized assumptions into a clean standalone recap", "Forward the entire raw chat transcript with no summary", "Ask the colleague to redo the analysis independently", "Assume the colleague doesn''t need any context"]'::jsonb,
 0, 'A focused summary turns a long working conversation into something clear and shareable, without you re-deriving it manually.',
 'advanced', 'scenario', 'Think about what''s actually useful to hand someone who wasn''t part of the process.', 27);

-- ---- prompting ----
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, difficulty, kind, hint, order_index) values
((select id from public.modules where slug='prompting'), null,
 'Which prompt is more likely to get a useful first draft?',
 '["Write a 3-paragraph product update email for existing customers, friendly tone, mentioning the new dashboard feature", "Write an email", "Make something good", "Do the email thing"]'::jsonb,
 0, 'The specific prompt states format, length, audience, tone, and content — everything Claude needs to know what "good" means here.',
 'beginner', 'mcq', 'Compare how much each option actually tells Claude about what you want.', 1),
((select id from public.modules where slug='prompting'), null,
 'Adding more adjectives like "great" or "amazing" to a prompt reliably improves Claude''s output.',
 '["True", "False"]'::jsonb,
 1, 'Vague adjectives are subjective and don''t tell Claude what to prioritize — concrete details like audience, format, and length do far more work.',
 'beginner', 'true_false', 'Think about whether an adjective actually specifies anything Claude can act on.', 2),
((select id from public.modules where slug='prompting'), null,
 'You want Claude to write in the voice of a specific expert. What technique are you using?',
 '["Role prompting", "Few-shot prompting", "Chain-of-thought prompting", "Zero-shot prompting"]'::jsonb,
 0, 'Asking Claude to respond as a particular persona or expert is role prompting.',
 'beginner', 'scenario', 'Think about what you''re asking Claude to pretend to be.', 3),
((select id from public.modules where slug='prompting'), null,
 'Showing Claude one or two examples of the exact output style you want, rather than describing it in words, is called _____ prompting.',
 '["few-shot", "zero-shot", "role-based", "open-ended"]'::jsonb,
 0, 'Few-shot prompting means providing examples ("shots") of the desired pattern.',
 'intermediate', 'fill_blank', 'The term counts how many examples you''re giving.', 4),
((select id from public.modules where slug='prompting'), null,
 'Why does specifying the audience for a piece of writing usually improve Claude''s output?',
 '["It narrows down vocabulary, depth, and tone to what actually fits that reader", "It has no effect on the output", "It only matters for very long documents", "It replaces the need for any other instructions"]'::jsonb,
 0, 'Audience context shapes word choice, depth, and framing — all things that determine whether the writing actually lands.',
 'intermediate', 'mcq', 'Think about how differently you''d explain the same idea to two different readers.', 5),
((select id from public.modules where slug='prompting'), null,
 'A role prompt (e.g., "respond as a data analyst") can change what Claude focuses on, not just its tone.',
 '["True", "False"]'::jsonb,
 0, 'A role shifts priorities and areas of focus, not just word choice — a "data analyst" role emphasizes different things than a "marketing writer" role would.',
 'intermediate', 'true_false', 'Consider whether a persona changes more than just the writing style.', 6),
((select id from public.modules where slug='prompting'), null,
 'You''ve given Claude a role, format instructions, and one example, but the tone still misses the mark. What''s the most likely fix?',
 '["Check whether the example itself actually demonstrates the tone you want \u2014 examples tend to carry more weight than written instructions", "Add even more adjectives describing the tone", "Remove the role instruction entirely", "Give up on using an example"]'::jsonb,
 0, 'Concrete examples strongly influence output — if the example doesn''t match the tone you''re asking for, it can override the written instruction.',
 'advanced', 'scenario', 'Think about which part of the prompt Claude is most likely to closely imitate.', 7),
((select id from public.modules where slug='prompting'), null,
 'Stacking a role, relevant context, and one or more examples together in a single prompt is sometimes called _____ prompting.',
 '["layered", "zero-shot", "single-pass", "blind"]'::jsonb,
 0, 'Layered prompting combines multiple techniques — role, context, and examples — for a more reliable result than relying on just one.',
 'advanced', 'fill_blank', 'Think about what''s happening when several techniques are combined at once.', 8),
((select id from public.modules where slug='prompting'), null,
 'When is few-shot prompting most worth the extra effort of writing an example?',
 '["When the output needs a specific style or structure that''s hard to fully describe in words", "For every single prompt, regardless of task", "Only when writing code, never for prose", "Never \u2014 descriptions are always sufficient"]'::jsonb,
 0, 'Examples shine when nuance or structure is hard to put into words — a concrete pattern communicates it more reliably.',
 'advanced', 'mcq', 'Think about tasks where describing "the right feel" in words is genuinely difficult.', 9),
((select id from public.modules where slug='prompting'), 'recruitment',
 'Which detail would make a job-description prompt most specific?',
 '["The exact role, seniority level, and must-have skills", "Just the word \"developer\"", "No details at all", "The company''s stock price"]'::jsonb,
 0, 'Concrete role details are what let Claude write a description that actually fits the position.',
 'beginner', 'mcq', 'Think about what a hiring manager would need to know to write this well.', 10),
((select id from public.modules where slug='prompting'), 'recruitment',
 'Outreach messages to five candidates all come out generic and interchangeable. What''s the fix?',
 '["Give Claude each candidate''s specific background and what drew you to their profile", "Ask Claude to write faster", "Send the same message to everyone anyway", "Remove all details to keep it simple"]'::jsonb,
 0, 'Specific, individual context is what makes outreach feel personalized rather than templated.',
 'intermediate', 'scenario', 'Think about what actually differs between five real candidates.', 11),
((select id from public.modules where slug='prompting'), 'recruitment',
 'Pasting one completed interview scorecard as an example is likely to match your team''s exact format more reliably than describing the format in a paragraph.',
 '["True", "False"]'::jsonb,
 0, 'A concrete example (few-shot) communicates exact structure and detail level more reliably than a written description.',
 'advanced', 'true_false', 'Think about which communicates a precise format more faithfully — words or a worked sample.', 12),
((select id from public.modules where slug='prompting'), 'marketing',
 'What is a "role" prompt in a marketing context?',
 '["Asking Claude to write as a specific persona, like a witty social media manager for a sneaker brand", "Asking Claude to summarize a role posting", "Giving Claude no instructions at all", "Asking for a list of job roles"]'::jsonb,
 0, 'A role prompt asks Claude to adopt a persona, shaping tone and priorities to match.',
 'beginner', 'mcq', 'Think about what you''re asking Claude to pretend to be.', 13),
((select id from public.modules where slug='prompting'), 'marketing',
 'Pasting three of your brand''s best-performing headlines before asking for new ones is an example of _____ prompting.',
 '["few-shot", "zero-shot", "role-based", "blind"]'::jsonb,
 0, 'Providing real examples of the pattern you want is few-shot prompting.',
 'intermediate', 'fill_blank', 'Think about the Project feature designed to hold reusable reference files.', 14),
((select id from public.modules where slug='prompting'), 'marketing',
 'Claude''s ad copy matches your brand''s tone but keeps missing the audience''s actual pain points. What''s missing from the prompt?',
 '["Audience context \u2014 who they are and what problem they''re trying to solve", "More adjectives describing the tone", "A stricter word count", "A different persona"]'::jsonb,
 0, 'Tone alone doesn''t convey what the audience actually cares about — that requires explicit audience context.',
 'advanced', 'scenario', 'Think about what''s different between "sounding right" and "speaking to the right problem."', 15),
((select id from public.modules where slug='prompting'), 'sales',
 'Why is "write a follow-up email to a prospect" a weak prompt?',
 '["It''s missing who the prospect is, what was discussed, and the desired next step", "It''s too long", "It uses the word \"prospect\"", "It doesn''t mention pricing"]'::jsonb,
 0, 'Without those specifics, Claude has to guess at details that determine whether the email is actually useful.',
 'beginner', 'mcq', 'Think about what information a real rep would need before writing this email.', 16),
((select id from public.modules where slug='prompting'), 'sales',
 'Telling Claude to "respond as a sales coach reviewing this pitch" is an example of role prompting.',
 '["True", "False"]'::jsonb,
 0, 'Assigning Claude a persona — here, a sales coach — is exactly what role prompting means.',
 'intermediate', 'true_false', 'Consider what kind of instruction this is.', 17),
((select id from public.modules where slug='prompting'), 'sales',
 'You want objection-handling replies that are direct but never pushy, matching your team''s style. What''s the most reliable approach?',
 '["Give Claude two or three real examples of your team''s best objection responses", "Just say \"be direct but not pushy\" and nothing else", "Ask for ten different tones and pick one later", "Avoid giving any examples so Claude isn''t biased"]'::jsonb,
 0, 'Concrete examples teach a nuanced balance like "direct but not pushy" more reliably than an abstract description.',
 'advanced', 'scenario', 'Think about how hard "direct but not pushy" is to fully capture in a short instruction.', 18),
((select id from public.modules where slug='prompting'), 'engineering',
 'What makes a code-request prompt specific?',
 '["Naming the language, exact inputs/outputs, and any constraints", "Just saying \"write a function\"", "Leaving out the programming language", "Asking for \"something efficient\" with no other detail"]'::jsonb,
 0, 'Concrete technical details are what let Claude produce code that actually fits your needs.',
 'beginner', 'mcq', 'Think about what a teammate would need to know to write this function correctly.', 19),
((select id from public.modules where slug='prompting'), 'engineering',
 'Asking Claude to review code "as a senior reviewer, focus only on performance and edge cases" is an example of _____ prompting.',
 '["role", "few-shot", "zero-shot", "format-only"]'::jsonb,
 0, 'Assigning a persona and focus area is role prompting — it narrows what Claude pays attention to.',
 'intermediate', 'fill_blank', 'Think about what kind of persona you''re asking Claude to take on.', 20),
((select id from public.modules where slug='prompting'), 'engineering',
 'You want Claude to write a new function that matches your team''s exact style conventions. What''s the most reliable approach?',
 '["Show it one function you''ve already written in that style as a few-shot example", "Describe your style guide in a single adjective like \"clean\"", "Avoid mentioning style at all", "Ask for the function in every possible style and pick the best"]'::jsonb,
 0, 'A concrete code example transmits style conventions — naming, structure, comments — more precisely than a description can.',
 'advanced', 'scenario', 'Think about what communicates coding style more precisely — words or a real sample.', 21),
((select id from public.modules where slug='prompting'), 'hr',
 'Why is "write a policy" too vague a prompt on its own?',
 '["It doesn''t say which policy, for what situation, or in what tone", "It''s grammatically incorrect", "It''s too short to be a real prompt", "Claude cannot write policies at all"]'::jsonb,
 0, 'Without those specifics, Claude has to guess at context that determines what a useful answer looks like.',
 'beginner', 'mcq', 'Think about how many different "policies" this could mean.', 22),
((select id from public.modules where slug='prompting'), 'hr',
 'Asking Claude to "respond as an employee relations specialist" only changes its tone, not what it focuses on.',
 '["True", "False"]'::jsonb,
 1, 'A role prompt shifts focus and priorities too — an employee relations specialist would emphasize fairness and compliance, not just sound a certain way.',
 'intermediate', 'true_false', 'Consider whether a persona changes more than just word choice.', 23),
((select id from public.modules where slug='prompting'), 'hr',
 'You need several FAQ answers in your company''s exact voice, but describing that voice in words keeps falling short. What should you do?',
 '["Paste two or three existing FAQ answers as few-shot examples", "Use stronger adjectives like \"very friendly\"", "Ask Claude to guess your company''s voice", "Give up and write them yourself with no AI help"]'::jsonb,
 0, 'Concrete examples transmit voice and structure more precisely than adjectives ever can.',
 'advanced', 'scenario', 'Think about what communicates a specific tone more reliably — a description or a real sample.', 24),
((select id from public.modules where slug='prompting'), 'finance',
 'What''s missing from the prompt "summarize this report"?',
 '["The audience, desired length, and what to emphasize", "The word \"report\"", "A greeting", "The file format"]'::jsonb,
 0, 'Those details determine what a genuinely useful summary looks like for this reader.',
 'beginner', 'mcq', 'Think about what changes a "good summary" from one reader to the next.', 25),
((select id from public.modules where slug='prompting'), 'finance',
 'Telling Claude "explain this like you''re briefing a first-time investor with no finance background" is an example of _____ prompting.',
 '["role", "few-shot", "zero-shot", "blind"]'::jsonb,
 0, 'Framing the audience/persona this way is role prompting — it adjusts vocabulary and depth accordingly.',
 'intermediate', 'fill_blank', 'Think about what persona or audience you''re describing here.', 26),
((select id from public.modules where slug='prompting'), 'finance',
 'You want variance-analysis commentary that matches your finance team''s exact structure. What''s the most reliable approach?',
 '["Provide one completed example of the commentary format as a few-shot example", "Describe \"our usual format\" in one sentence", "Skip formatting instructions entirely", "Ask for five different formats and merge them"]'::jsonb,
 0, 'A concrete example is far more reliable than a verbal description for conveying an exact structural format.',
 'advanced', 'scenario', 'Think about what communicates an exact structure more precisely — words or a worked sample.', 27);

-- ---- projects ----
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, difficulty, kind, hint, order_index) values
((select id from public.modules where slug='projects'), null,
 'What is a Claude Project?',
 '["A dedicated space with custom instructions and shared knowledge available to every chat inside it", "A single very long conversation", "A way to delete old chats", "A setting that changes Claude''s writing speed"]'::jsonb,
 0, 'A Project bundles standing instructions and reference material that every chat within it can draw on.',
 'beginner', 'mcq', 'Think about what''s shared across multiple chats, rather than living in just one.', 1),
((select id from public.modules where slug='projects'), null,
 'Custom instructions set in a Project automatically apply to every new chat started inside that Project.',
 '["True", "False"]'::jsonb,
 0, 'That''s the point of custom instructions — they''re standing guidance applied across the Project''s conversations.',
 'beginner', 'true_false', 'Consider what "standing instructions" implies about future chats.', 2),
((select id from public.modules where slug='projects'), null,
 'You upload your company''s style guide to a Project instead of pasting it into every chat. What are you using?',
 '["Project knowledge", "A new custom model", "A chat title", "A saved reply"]'::jsonb,
 0, 'Reference files added to a Project are its project knowledge — available to every chat inside it.',
 'beginner', 'scenario', 'Think about what category of Project feature holds reference documents.', 3),
((select id from public.modules where slug='projects'), null,
 'Setting up a Project''s instructions and knowledge once, so every future chat automatically has that context, is called _____ context.',
 '["persistent", "temporary", "hidden", "exported"]'::jsonb,
 0, 'Persistent context sticks around across every chat in the Project, unlike context in a single conversation.',
 'intermediate', 'fill_blank', 'Think of a word meaning "lasting" or "carried forward."', 4),
((select id from public.modules where slug='projects'), null,
 'What''s the main time-saving benefit of using a Project for recurring work?',
 '["You set up background and preferences once instead of re-explaining them in every new chat", "Projects make Claude respond faster", "Projects automatically write your final answer for you", "Projects remove the need to review any output"]'::jsonb,
 0, 'The core benefit is not re-typing the same context every time — it''s already there for every chat in the Project.',
 'intermediate', 'mcq', 'Think about what you''d otherwise have to repeat in every fresh chat.', 5),
((select id from public.modules where slug='projects'), null,
 'Updating a Project''s knowledge files retroactively changes the answers Claude already gave in old chats within that Project.',
 '["True", "False"]'::jsonb,
 1, 'Updated knowledge affects future chats going forward — it doesn''t rewrite responses that were already given.',
 'intermediate', 'true_false', 'Consider whether a knowledge update reaches backward or only forward in time.', 6),
((select id from public.modules where slug='projects'), null,
 'A Project''s knowledge base has grown large with some outdated files still mixed in. What''s the risk?',
 '["Outdated material can crowd out what''s relevant and lead to answers based on stale information", "There''s no risk \u2014 more knowledge is always strictly better", "Claude will automatically ignore anything old", "The Project will stop working entirely"]'::jsonb,
 0, 'A cluttered, unpruned knowledge base can cause Claude to draw on outdated or conflicting material instead of what''s current.',
 'advanced', 'scenario', 'Think about what happens when old and new reference material sit side by side.', 7),
((select id from public.modules where slug='projects'), null,
 'The risk of a Project''s reference material becoming outdated and degrading answer quality is sometimes called knowledge _____.',
 '["staleness", "expansion", "encryption", "duplication"]'::jsonb,
 0, '"Knowledge staleness" describes outdated reference material quietly undermining the quality of Claude''s answers.',
 'advanced', 'fill_blank', 'Think of a word describing food or information that''s gone past its useful date.', 8),
((select id from public.modules where slug='projects'), null,
 'A Project defaults to a formal tone, but one chat needs something more casual. What should you do?',
 '["State the override explicitly in that chat \u2014 in-conversation instructions take precedence for that conversation", "Nothing can be done \u2014 the Project''s tone is locked forever", "Delete the Project and start over", "Create an entirely new account"]'::jsonb,
 0, 'An explicit in-chat instruction generally overrides the Project''s standing default for that specific conversation.',
 'advanced', 'mcq', 'Think about which instruction is more specific and recent — the Project default or what you just typed.', 9),
((select id from public.modules where slug='projects'), 'recruitment',
 'What might a recruiter store as project knowledge in a Project?',
 '["Outreach templates and the company''s tone-of-voice guide", "Random unrelated files", "Nothing \u2014 Projects can''t hold files", "Only candidate resumes with no other context"]'::jsonb,
 0, 'Reusable reference material like templates and style guides is exactly what project knowledge is for.',
 'beginner', 'mcq', 'Think about what a recruiter re-uses across many candidate conversations.', 10),
((select id from public.modules where slug='projects'), 'recruitment',
 'Explaining your company''s interview process once in a Project''s custom instructions means every future chat in that Project already knows it.',
 '["True", "False"]'::jsonb,
 0, 'Custom instructions apply automatically to every chat inside that Project, so it doesn''t need to be re-explained.',
 'intermediate', 'true_false', 'Consider what "custom instructions" are designed to do across chats.', 11),
((select id from public.modules where slug='projects'), 'recruitment',
 'A Hiring Project''s knowledge includes an outdated job-leveling guide replaced last quarter. What should the recruiter do?',
 '["Remove or update the outdated file so Claude doesn''t apply old criteria", "Leave it \u2014 old and new guides rarely conflict", "Delete the whole Project", "Ignore it since Claude won''t reference old files"]'::jsonb,
 0, 'Stale reference material can cause Claude to apply criteria that no longer match current standards.',
 'advanced', 'scenario', 'Think about what happens when outdated and current guidance sit in the same knowledge base.', 12),
((select id from public.modules where slug='projects'), 'marketing',
 'What''s a natural use of a Project for a marketing team?',
 '["A \"Brand Voice\" Project holding style guides and past campaigns", "A Project with no files or instructions at all", "A single chat used for everything, including unrelated tasks", "A Project that only stores images"]'::jsonb,
 0, 'Centralizing brand reference material in a Project keeps every content request consistent with brand voice.',
 'beginner', 'mcq', 'Think about what marketing content needs to stay consistent across many requests.', 13),
((select id from public.modules where slug='projects'), 'marketing',
 'Uploading brand guidelines once into a Project instead of pasting them into every content chat is an example of using _____.',
 '["project knowledge", "a new device", "a chat export", "a browser extension"]'::jsonb,
 0, 'Project knowledge is exactly this — persistent reference material shared across the Project''s chats.',
 'intermediate', 'fill_blank', 'Think about the Project feature designed to hold reusable reference files.', 14),
((select id from public.modules where slug='projects'), 'marketing',
 'A Campaigns Project defaults to a bold, energetic voice, but this week''s brief needs a somber, empathetic tone. What''s the best move?',
 '["State the tone override explicitly in that chat", "Create an entirely new account for this one brief", "Wait for the Project''s default to change on its own", "Ignore the mismatch and use the bold voice anyway"]'::jsonb,
 0, 'An explicit in-chat instruction takes precedence over the Project''s standing tone default for that conversation.',
 'advanced', 'scenario', 'Think about which is more specific to this one task — the Project default or what you type now.', 15),
((select id from public.modules where slug='projects'), 'sales',
 'What could a sales rep store in a "Deal Prep" Project?',
 '["Product one-pagers and objection-handling notes", "Nothing relevant to sales", "Random personal files", "Only email signatures"]'::jsonb,
 0, 'Reusable sales reference material is exactly what project knowledge is designed to hold.',
 'beginner', 'mcq', 'Think about what a rep re-uses across many different deals.', 16),
((select id from public.modules where slug='projects'), 'sales',
 'A Project lets you start a fresh chat per account while still sharing common reference material like product info across all of them.',
 '["True", "False"]'::jsonb,
 0, 'That''s a key benefit of Projects — clean per-chat context combined with shared background knowledge.',
 'intermediate', 'true_false', 'Consider what stays shared versus what starts fresh with each new chat in a Project.', 17),
((select id from public.modules where slug='projects'), 'sales',
 'An Enterprise Deals Project''s knowledge still lists pricing from two quarters ago. What''s the risk?',
 '["Claude might produce proposals or talking points based on outdated numbers", "No risk \u2014 Claude always uses the latest public pricing automatically", "The Project will refuse to function", "Old pricing files are automatically deleted"]'::jsonb,
 0, 'Outdated reference material in project knowledge can silently feed into current work unless it''s updated.',
 'advanced', 'scenario', 'Think about what happens when Claude has no way to know the pricing file is stale.', 18),
((select id from public.modules where slug='projects'), 'engineering',
 'What might an engineer add to a Project''s knowledge for a specific codebase?',
 '["Architecture notes and coding conventions", "Nothing \u2014 Projects don''t support technical files", "Random unrelated screenshots", "Only the final compiled binary"]'::jsonb,
 0, 'Technical reference material like architecture notes is exactly what project knowledge is designed for.',
 'beginner', 'mcq', 'Think about what context a new teammate would need about this codebase.', 19),
((select id from public.modules where slug='projects'), 'engineering',
 'Adding a style guide once as project knowledge instead of pasting it into every new chat is an example of _____ context.',
 '["persistent", "one-time", "hidden", "exported"]'::jsonb,
 0, 'Persistent context is set up once and remains available across every chat in the Project.',
 'intermediate', 'fill_blank', 'Think of a word meaning "sticks around" across future chats.', 20),
((select id from public.modules where slug='projects'), 'engineering',
 'A team''s Project knowledge includes a deprecated API''s docs alongside the current API''s docs. What''s the risk?',
 '["Claude may mix guidance from the old and new APIs, producing subtly broken suggestions", "There''s no risk since Claude always prefers the newest file", "The deprecated docs will be auto-deleted", "The Project will crash"]'::jsonb,
 0, 'Conflicting reference material can lead to suggestions that blend outdated and current guidance.',
 'advanced', 'scenario', 'Think about what happens when two versions of the same reference disagree.', 21),
((select id from public.modules where slug='projects'), 'hr',
 'What''s a good use of a Project for HR?',
 '["An \"Employee Policies\" Project holding the current handbook", "A Project with no organizing theme at all", "Storing only employees'' personal contact info", "A Project used for one single unrelated chat"]'::jsonb,
 0, 'Centralizing current policy documents keeps answers consistent across every policy-related chat.',
 'beginner', 'mcq', 'Think about what needs to stay consistent when many people ask policy questions.', 22),
((select id from public.modules where slug='projects'), 'hr',
 'Every chat inside an HR Project can reference the same up-to-date handbook without it being re-uploaded each time.',
 '["True", "False"]'::jsonb,
 0, 'That''s the point of project knowledge — one upload, available to every chat in that Project.',
 'intermediate', 'true_false', 'Consider what "shared" reference material implies about needing to re-upload.', 23),
((select id from public.modules where slug='projects'), 'hr',
 'An Onboarding Project defaults to a warm, welcoming tone, but this week you''re drafting a formal compliance notice. What should you do?',
 '["Explicitly state the tone you need for that specific chat", "Nothing \u2014 the default tone can never be changed", "Create a brand-new account just for this notice", "Delete the Project''s custom instructions permanently"]'::jsonb,
 0, 'An in-chat instruction overrides the Project''s default tone just for that one conversation.',
 'advanced', 'scenario', 'Think about which instruction is more specific — the standing default or what you type right now.', 24),
((select id from public.modules where slug='projects'), 'finance',
 'What could a finance team store as project knowledge in a "Monthly Close" Project?',
 '["The chart of accounts and prior month templates", "Nothing \u2014 finance data shouldn''t go in Projects", "Only a list of employee names", "Random unrelated spreadsheets"]'::jsonb,
 0, 'Reusable reference material like the chart of accounts is exactly what project knowledge supports.',
 'beginner', 'mcq', 'Think about what''s re-used every single month during close.', 25),
((select id from public.modules where slug='projects'), 'finance',
 'Everyone''s chats inside a shared Project draw on the same custom instructions and knowledge files, which helps keep outputs _____ across a team.',
 '["consistent", "random", "private", "slower"]'::jsonb,
 0, 'Shared standing instructions and knowledge keep multiple people''s outputs aligned rather than drifting apart.',
 'intermediate', 'fill_blank', 'Think about what a shared standard does for a team''s output.', 26),
((select id from public.modules where slug='projects'), 'finance',
 'A Forecasting Project''s knowledge base has grown to include several superseded versions of the assumptions file. What should the team do?',
 '["Prune the outdated versions so Claude reliably picks the current assumptions", "Add even more versions for completeness", "Leave it \u2014 Claude will always guess correctly", "Rename the Project instead of fixing the files"]'::jsonb,
 0, 'A cluttered, conflicting knowledge base makes it harder to reliably surface the correct, current assumptions.',
 'advanced', 'scenario', 'Think about what happens when multiple conflicting versions of the same file coexist.', 27);

-- ---- artifacts ----
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, difficulty, kind, hint, order_index) values
((select id from public.modules where slug='artifacts'), null,
 'What is a Claude Artifact?',
 '["A separate editable pane for substantial content like documents, code, or visuals", "A type of chat message that disappears after reading", "A setting for changing Claude''s response speed", "A file format only used for images"]'::jsonb,
 0, 'Artifacts render substantial, self-contained content in their own view so you can see, edit, and iterate on it.',
 'beginner', 'mcq', 'Think about what shows up in a side panel separate from the chat itself.', 1),
((select id from public.modules where slug='artifacts'), null,
 'Only code can appear as an Artifact — documents and visuals always stay in the chat.',
 '["True", "False"]'::jsonb,
 1, 'Artifacts can hold documents, code, websites, diagrams, and interactive apps — not just code.',
 'beginner', 'true_false', 'Consider the range of content types Artifacts are designed to hold.', 2),
((select id from public.modules where slug='artifacts'), null,
 'Claude builds a working interactive calculator you can click and test in a side panel. What is this?',
 '["An Artifact", "A chat export", "A saved template", "A browser plugin"]'::jsonb,
 0, 'A self-contained, interactive piece of content like this is exactly what Artifacts are designed to render.',
 'beginner', 'scenario', 'Think about where substantial, usable content shows up separate from the conversation.', 3),
((select id from public.modules where slug='artifacts'), null,
 'Asking Claude to revise something already shown in the side panel, rather than rewriting it in chat, is called _____ on an Artifact.',
 '["iterating", "exporting", "deleting", "archiving"]'::jsonb,
 0, 'Iterating means making targeted follow-up edits to the Artifact that''s already there.',
 'intermediate', 'fill_blank', 'Think of a word meaning "making repeated refinements."', 4),
((select id from public.modules where slug='artifacts'), null,
 'Why are Artifacts useful for content you plan to keep revising?',
 '["They live in a persistent, separate view instead of being buried in scrolling chat messages", "They automatically save to your hard drive", "They can never be edited once created", "They only work for images"]'::jsonb,
 0, 'A persistent, standalone view is much easier to keep referring back to and editing than hunting through a long chat.',
 'intermediate', 'mcq', 'Think about what makes something easy to find and revise later.', 5),
((select id from public.modules where slug='artifacts'), null,
 'Asking Claude to change one small detail in an Artifact, like a header color, causes it to rebuild the entire Artifact from nothing.',
 '["True", "False"]'::jsonb,
 1, 'A targeted request typically results in a targeted edit to the existing Artifact, not a full rebuild.',
 'intermediate', 'true_false', 'Consider whether a small request should require throwing away everything else.', 6),
((select id from public.modules where slug='artifacts'), null,
 'You''ve made many small tweaks to a dashboard Artifact and now want a completely different visual style. What''s the better approach?',
 '["Clearly describe the new direction and let Claude regenerate significant portions", "Keep making tiny incremental nudges toward the new style", "Start an entirely new chat with no context at all", "Ask Claude to undo every previous edit one by one"]'::jsonb,
 0, 'Small iterative edits work well for refinements, but a major style change is usually cleaner as a deliberate regeneration.',
 'advanced', 'scenario', 'Think about whether this change is a tweak or an overhaul.', 7),
((select id from public.modules where slug='artifacts'), null,
 'Deciding whether a requested change warrants a small tweak versus a full regeneration of an Artifact is a judgment call sometimes called _____ scope.',
 '["iteration", "export", "archive", "render"]'::jsonb,
 0, '"Iteration scope" describes weighing how big a change is before deciding how to request it.',
 'advanced', 'fill_blank', 'Think about what you''re scoping — the size of the edit.', 8),
((select id from public.modules where slug='artifacts'), null,
 'Why might you deliberately ask for something as an Artifact rather than just having Claude describe it in chat?',
 '["When the deliverable is meant to be reused, shared, or interacted with as a finished thing", "Because Artifacts are always shorter than chat replies", "Because chat replies cannot contain any code", "Artifacts are required for every single request"]'::jsonb,
 0, 'Artifacts are best suited to standalone, reusable, or interactive deliverables, not general conversation.',
 'advanced', 'mcq', 'Think about what kind of output benefits from living outside the flow of conversation.', 9),
((select id from public.modules where slug='artifacts'), 'recruitment',
 'What''s a good use of an Artifact for a recruiter?',
 '["A polished candidate scorecard template", "A single one-word chat reply", "A private note only Claude can see", "An email signature block"]'::jsonb,
 0, 'Substantial, reusable content like a scorecard template is a good fit for an Artifact.',
 'beginner', 'mcq', 'Think about what''s substantial and reusable enough to deserve its own editable view.', 10),
((select id from public.modules where slug='artifacts'), 'recruitment',
 'Asking Claude to "add a column for years of experience" to a candidate comparison table Artifact will update the existing table rather than create a brand-new one.',
 '["True", "False"]'::jsonb,
 0, 'Targeted requests typically result in Claude editing the existing Artifact directly.',
 'intermediate', 'true_false', 'Consider whether a specific, small request needs a whole new Artifact.', 11),
((select id from public.modules where slug='artifacts'), 'recruitment',
 'A hiring dashboard Artifact has had many small tweaks and now needs to switch from a table layout to a visual card layout entirely. What''s the better move?',
 '["Ask for a rebuild \u2014 describe the new card-based design and let Claude regenerate it", "Keep nudging the table layout toward cards one tiny change at a time", "Start over with a completely blank chat and no context", "Give up on using an Artifact for this"]'::jsonb,
 0, 'A major structural change like switching layouts entirely is better handled as a deliberate regeneration.',
 'advanced', 'scenario', 'Think about whether this is a small tweak or a fundamentally different structure.', 12),
((select id from public.modules where slug='artifacts'), 'marketing',
 'What kind of marketing content fits well as an Artifact?',
 '["A formatted content calendar or landing page mockup", "A single emoji reaction", "A one-word chat confirmation", "A private setting only visible to Claude"]'::jsonb,
 0, 'Substantial, structured marketing deliverables are exactly what Artifacts are meant to hold.',
 'beginner', 'mcq', 'Think about what''s worth its own editable view versus a quick chat reply.', 13),
((select id from public.modules where slug='artifacts'), 'marketing',
 'Asking Claude to "make the CTA button bigger" on a landing page Artifact already open in the side panel is an example of _____ on an Artifact.',
 '["iterating", "deleting", "exporting", "hiding"]'::jsonb,
 0, 'This is a targeted follow-up edit to existing content — iterating on the Artifact.',
 'intermediate', 'fill_blank', 'Think of the term for making a follow-up refinement to something already shown.', 14),
((select id from public.modules where slug='artifacts'), 'marketing',
 'A campaign one-pager Artifact has been through a dozen small edits and no longer matches the clean structure you wanted. What''s the better fix?',
 '["Describe the structure you actually want and ask Claude to regenerate it", "Keep making one more small edit indefinitely", "Abandon Artifacts and only use plain chat text from now on", "Ask a coworker to manually reformat it instead"]'::jsonb,
 0, 'Many small edits can compound into a messier result than a clean, deliberate regeneration.',
 'advanced', 'scenario', 'Think about what happens after a dozen incremental patches versus a fresh, clearly-specified rebuild.', 15),
((select id from public.modules where slug='artifacts'), 'sales',
 'What''s a natural Artifact for a sales rep to request?',
 '["A formatted proposal document or pricing comparison table", "A single-word chat reply", "A private internal note only visible to Claude", "A random unrelated image"]'::jsonb,
 0, 'Reviewable, shareable, structured content like a proposal is a strong fit for an Artifact.',
 'beginner', 'mcq', 'Think about what''s meant to be reviewed and eventually shared as a finished piece.', 16),
((select id from public.modules where slug='artifacts'), 'sales',
 'Asking Claude to "reword the executive summary, keep everything else" on a proposal Artifact will edit just that section rather than the whole document.',
 '["True", "False"]'::jsonb,
 0, 'A specific, scoped request results in a scoped edit to just that part of the Artifact.',
 'intermediate', 'true_false', 'Consider whether a narrowly-worded request needs to touch unrelated sections.', 17),
((select id from public.modules where slug='artifacts'), 'sales',
 'A proposal Artifact has been tweaked so many times its structure has become inconsistent. What''s the better approach now?',
 '["Describe the ideal structure and ask for a fresh regenerated version", "Keep patching individual inconsistencies one at a time forever", "Delete the Artifact and rebuild the whole proposal by hand", "Ignore the inconsistency and send it as-is"]'::jsonb,
 0, 'A full regeneration from a clear structure often beats continuing to patch something that''s drifted through many edits.',
 'advanced', 'scenario', 'Think about whether more small patches will fix the underlying structural drift.', 18),
((select id from public.modules where slug='artifacts'), 'engineering',
 'Why would Claude render code as an Artifact instead of just showing it in the chat?',
 '["Substantial or runnable code is typically shown separately so you can view, edit, and interact with it", "Code can never appear inside a chat message", "Artifacts are required for every code request, no matter how tiny", "It makes the code run faster"]'::jsonb,
 0, 'A separate, editable, interactive view is more useful than plain text buried in a chat for real code.',
 'beginner', 'mcq', 'Think about what makes code easier to actually use and modify.', 19),
((select id from public.modules where slug='artifacts'), 'engineering',
 'Asking Claude to "add a field for the discount percentage" to an interactive tool Artifact is an example of _____ on the Artifact.',
 '["iterating", "archiving", "exporting", "renaming"]'::jsonb,
 0, 'This is a targeted follow-up change — iterating on the existing Artifact rather than rebuilding it.',
 'intermediate', 'fill_blank', 'Think of the term for a follow-up refinement to something already generated.', 20),
((select id from public.modules where slug='artifacts'), 'engineering',
 'An Artifact-based prototype has grown tangled through many incremental feature requests. What''s the better next step?',
 '["Describe the cleaned-up structure you want and let Claude regenerate it", "Add one more small patch on top of the existing tangle", "Abandon the prototype entirely with no further action", "Ask Claude to explain the tangle without changing anything"]'::jsonb,
 0, 'Incremental patches on an already-tangled base tend to compound the mess — a deliberate rebuild is often cleaner.',
 'advanced', 'scenario', 'Think about whether one more small patch will actually untangle the structure.', 21),
((select id from public.modules where slug='artifacts'), 'hr',
 'What HR content is a good fit for an Artifact?',
 '["A formatted onboarding checklist or polished policy handout", "A single emoji confirmation", "A private setting only Claude can see", "A one-word chat reply"]'::jsonb,
 0, 'Substantial, reusable HR documents are a strong fit for Artifacts.',
 'beginner', 'mcq', 'Think about what''s worth its own editable, reusable view.', 22),
((select id from public.modules where slug='artifacts'), 'hr',
 'Asking Claude to "shorten the PTO section" on a handbook Artifact already open will typically edit just that section.',
 '["True", "False"]'::jsonb,
 0, 'A specific, targeted request results in a targeted edit to that part of the existing Artifact.',
 'intermediate', 'true_false', 'Consider whether a narrowly scoped request needs to touch the whole document.', 23),
((select id from public.modules where slug='artifacts'), 'hr',
 'An onboarding checklist Artifact has been edited piecemeal so many times that sections now overlap and repeat. What''s the better fix?',
 '["Ask Claude to regenerate the checklist from a clear, current outline", "Trim the overlaps one more time and hope it holds", "Split it into ten separate Artifacts", "Ignore the overlaps since they''re minor"]'::jsonb,
 0, 'A regeneration from a clean outline avoids carrying forward redundancy that accumulated through many small edits.',
 'advanced', 'scenario', 'Think about whether trimming again will fix the underlying redundancy or just patch around it.', 24),
((select id from public.modules where slug='artifacts'), 'finance',
 'What''s a good use of an Artifact for finance work?',
 '["A formatted budget summary or variance-analysis table", "A single-word chat confirmation", "A private setting only visible internally to Claude", "An unrelated casual comment"]'::jsonb,
 0, 'Structured, substantial financial documents are a strong fit for Artifacts.',
 'beginner', 'mcq', 'Think about what''s structured and substantial enough to deserve its own editable view.', 25),
((select id from public.modules where slug='artifacts'), 'finance',
 'Asking Claude to "update only the Q3 column with these figures" on a forecast table Artifact is an example of _____ on the Artifact.',
 '["iterating", "deleting", "hiding", "duplicating"]'::jsonb,
 0, 'This is a scoped follow-up edit — iterating on the existing table rather than rebuilding it.',
 'intermediate', 'fill_blank', 'Think of the term for a targeted follow-up change to something already shown.', 26),
((select id from public.modules where slug='artifacts'), 'finance',
 'A budget Artifact has accumulated many small structural tweaks over weeks and no longer matches your reporting standard. What''s the better approach?',
 '["Describe the standard structure you need and ask Claude to regenerate the table", "Keep making one more small fix and hope it converges", "Manually rebuild it outside of Claude entirely", "Leave it as-is since small tweaks rarely matter"]'::jsonb,
 0, 'A clean rebuild from a clear standard avoids compounding small inconsistencies accumulated from prior edits.',
 'advanced', 'scenario', 'Think about whether one more small tweak will resolve the underlying structural drift.', 27);

-- ---- tool-use ----
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, difficulty, kind, hint, order_index) values
((select id from public.modules where slug='tool-use'), null,
 'What does it mean for Claude to "use a tool"?',
 '["It calls on an external capability, like web search, to help answer your request", "It changes its own personality permanently", "It stops responding to further messages", "It deletes the current conversation"]'::jsonb,
 0, 'Tool use means Claude reaches beyond its own built-in knowledge to pull in outside capabilities like search or connected data.',
 'beginner', 'mcq', 'Think about what "external capability" Claude might reach for beyond what it already knows.', 1),
((select id from public.modules where slug='tool-use'), null,
 'Claude''s training data includes every event up to the current date, so web search is never necessary.',
 '["True", "False"]'::jsonb,
 1, 'Claude''s training data has a cutoff, so web search fills in current or recent information beyond that point.',
 'beginner', 'true_false', 'Consider whether Claude''s knowledge has a fixed cutoff point.', 2),
((select id from public.modules where slug='tool-use'), null,
 'You ask Claude about a news event from this morning. What capability helps it answer accurately?',
 '["Web search", "Its training data alone", "A calculator", "A spellchecker"]'::jsonb,
 0, 'Very recent events fall outside Claude''s training data, so a live web search is what supplies current information.',
 'beginner', 'scenario', 'Think about what''s needed for information that''s too recent to be in training data.', 3),
((select id from public.modules where slug='tool-use'), null,
 'A pre-built integration that lets Claude read from or act on a specific external app, like a calendar, is called a _____.',
 '["connector", "cache", "cutoff", "checkpoint"]'::jsonb,
 0, 'A connector links Claude to a specific external app so it can read or act on real data there.',
 'intermediate', 'fill_blank', 'Think of a word describing something that links two systems together.', 4),
((select id from public.modules where slug='tool-use'), null,
 'Why might Claude search the web instead of answering purely from what it already knows?',
 '["When a question depends on current or time-sensitive information beyond its training cutoff", "Because it always prefers search over its own knowledge", "Because search is required for every single question", "Because its own knowledge is never reliable"]'::jsonb,
 0, 'Search is most useful specifically for current, time-sensitive, or very recent information that training data can''t cover.',
 'intermediate', 'mcq', 'Think about what kind of question training data alone can''t answer.', 5),
((select id from public.modules where slug='tool-use'), null,
 'MCP (Model Context Protocol) is an open standard for connecting Claude to external tools and data sources.',
 '["True", "False"]'::jsonb,
 0, 'MCP is exactly that — a standardized way for Claude to connect to outside tools and data consistently.',
 'intermediate', 'true_false', 'Consider what the acronym is describing — a protocol for what kind of connection.', 6),
((select id from public.modules where slug='tool-use'), null,
 'Claude searches the web and summarizes a statistic you plan to use in an important decision. What''s the safest next step?',
 '["Check the original source before relying on the summarized number", "Use it immediately without checking, since search results are always accurate", "Ignore the search result entirely", "Ask Claude to search again for the exact same thing"]'::jsonb,
 0, 'Summaries can be imprecise or based on an outdated source, so decision-critical numbers deserve direct verification.',
 'advanced', 'scenario', 'Think about what could go wrong between the original source and a quick summary of it.', 7),
((select id from public.modules where slug='tool-use'), null,
 'Staying aware of what a connector or tool is actually doing on your behalf — rather than trusting it blindly — is sometimes called tool-use _____.',
 '["oversight", "automation", "latency", "encryption"]'::jsonb,
 0, 'Tool-use oversight means keeping an eye on the real actions tools take, since they can affect real systems, not just chat replies.',
 'advanced', 'fill_blank', 'Think of a word meaning "keeping watch" over what''s happening.', 8),
((select id from public.modules where slug='tool-use'), null,
 'Why does connector access deserve more caution than a plain chat answer?',
 '["A connector can read or write real data in an external system, so mistakes have real consequences", "Connectors always require a paid subscription", "Connectors are slower than typing manually", "Connectors can only be used once per day"]'::jsonb,
 0, 'Because a connector interacts with a live external system, an error acted on through it can affect real data, not just produce a wrong chat message.',
 'advanced', 'mcq', 'Think about what''s different between a wrong answer in chat and a wrong action taken in a real system.', 9),
((select id from public.modules where slug='tool-use'), 'recruitment',
 'How might web search help a recruiter using Claude?',
 '["Looking up current salary benchmarks or recent company news", "Automatically hiring a candidate", "Deleting old job postings", "Changing Claude''s writing tone permanently"]'::jsonb,
 0, 'Web search is useful for current information like salary data or recent news that changes over time.',
 'beginner', 'mcq', 'Think about what kind of recruiting information changes frequently and needs to be current.', 10),
((select id from public.modules where slug='tool-use'), 'recruitment',
 'A candidate''s public professional presence can change frequently, making web search a good fit for checking it.',
 '["True", "False"]'::jsonb,
 0, 'Since public profiles update often, a live search is more likely to reflect current information than training data alone.',
 'intermediate', 'true_false', 'Consider how often a public profile might change compared to Claude''s training cutoff.', 11),
((select id from public.modules where slug='tool-use'), 'recruitment',
 'A calendar connector now auto-schedules interviews based on availability it reads directly. What should the recruiter do?',
 '["Closely check the first several bookings it makes", "Trust every booking immediately with no review", "Disable Claude entirely for scheduling forever", "Only use the connector for candidates, never interviewers"]'::jsonb,
 0, 'Because this connector takes real scheduling actions, an early review catches misreads before they become real conflicts.',
 'advanced', 'scenario', 'Think about what happens if the connector misreads an availability slot.', 12),
((select id from public.modules where slug='tool-use'), 'marketing',
 'Why might a marketer use web search inside a Claude chat?',
 '["To pull in current trends or competitor campaigns beyond Claude''s training cutoff", "To automatically publish a campaign", "To permanently change the brand''s logo", "To delete outdated content"]'::jsonb,
 0, 'Web search fills in current information, like recent trends, that falls outside Claude''s training data.',
 'beginner', 'mcq', 'Think about what kind of marketing information goes stale quickly.', 13),
((select id from public.modules where slug='tool-use'), 'marketing',
 'Connecting Claude to your analytics or content-management tool so it can read real campaign data directly is an example of using a _____.',
 '["connector", "cache", "font", "template"]'::jsonb,
 0, 'A connector is the integration that lets Claude read from a specific external app like an analytics tool.',
 'intermediate', 'fill_blank', 'Think of the term for a pre-built link between Claude and an external app.', 14),
((select id from public.modules where slug='tool-use'), 'marketing',
 'Claude searched the web for a competitor''s pricing and the number looks oddly specific. What should you do before using it in a strategy doc?',
 '["Check the original source directly", "Use it immediately without any verification", "Assume it must be wrong and discard it", "Ask a different AI tool instead"]'::jsonb,
 0, 'Decision-critical figures deserve direct verification since summarized search results can occasionally be imprecise.',
 'advanced', 'scenario', 'Think about what could go wrong between the original source and a summarized version of it.', 15),
((select id from public.modules where slug='tool-use'), 'sales',
 'How could web search help a sales rep prep for a call?',
 '["Pulling recent news about the prospect''s company, like funding or leadership changes", "Automatically closing the deal", "Changing the CRM''s data permanently", "Deleting old call notes"]'::jsonb,
 0, 'Recent company news is exactly the kind of current information web search is good for.',
 'beginner', 'mcq', 'Think about what kind of prospect information changes and needs to be current.', 16),
((select id from public.modules where slug='tool-use'), 'sales',
 'A connector to your CRM lets Claude read real, current deal data instead of you manually copying it in.',
 '["True", "False"]'::jsonb,
 0, 'That''s exactly what a connector is for — giving Claude direct access to live data in an external tool.',
 'intermediate', 'true_false', 'Consider what a connector is designed to let Claude do with an external system.', 17),
((select id from public.modules where slug='tool-use'), 'sales',
 'A CRM connector now updates deal stages automatically based on your conversation notes. What should you do?',
 '["Review its updates before trusting them fully", "Let it update everything with no review, since it''s automated", "Disconnect the CRM connector permanently", "Only use it for deals under a certain size"]'::jsonb,
 0, 'Since this connector writes real data into your CRM, an inaccurate mapping could quietly corrupt your actual pipeline.',
 'advanced', 'scenario', 'Think about what happens if the connector maps a note to the wrong deal stage.', 18),
((select id from public.modules where slug='tool-use'), 'engineering',
 'Why might an engineer use web search inside a Claude chat?',
 '["To look up current documentation or a framework update released after training cutoff", "To automatically deploy code to production", "To permanently delete a repository", "To compile code faster"]'::jsonb,
 0, 'Web search helps with information that''s changed or been released since Claude''s training data cutoff.',
 'beginner', 'mcq', 'Think about what kind of technical information changes frequently after a model is trained.', 19),
((select id from public.modules where slug='tool-use'), 'engineering',
 'The open standard that lets Claude connect consistently to developer tools like an issue tracker or internal API is called _____.',
 '["MCP (Model Context Protocol)", "HTTP", "JSON", "REST"]'::jsonb,
 0, 'MCP is the standard designed specifically for connecting Claude to external tools and data sources.',
 'intermediate', 'fill_blank', 'Think of the term introduced specifically for tool and data connections, not general web protocols.', 20),
((select id from public.modules where slug='tool-use'), 'engineering',
 'Claude, connected to your issue tracker via MCP, proposes closing tickets based on its read of recent commits. What should you do?',
 '["Review its proposed actions before anything gets closed", "Let it close every ticket automatically without review", "Disable the connector and never reconnect it", "Ignore the proposal entirely without reading it"]'::jsonb,
 0, 'A connector acting on a misread commit history could close a real ticket incorrectly, so reviewing proposed actions first matters.',
 'advanced', 'scenario', 'Think about what happens if the commit history is misread before a ticket gets closed.', 21),
((select id from public.modules where slug='tool-use'), 'hr',
 'How might web search help someone working in HR?',
 '["Looking up current employment law changes or benefits benchmarks", "Automatically terminating an employee", "Permanently deleting HR records", "Changing company policy without review"]'::jsonb,
 0, 'Employment law and benchmark data change over time, making them a good fit for a current web search.',
 'beginner', 'mcq', 'Think about what kind of HR information shifts and needs to stay current.', 22),
((select id from public.modules where slug='tool-use'), 'hr',
 'Connecting Claude to your HRIS via a connector lets it read real, current employee data directly instead of relying on manually exported reports.',
 '["True", "False"]'::jsonb,
 0, 'That''s the benefit of a connector — direct access to live data rather than manual copy-pasting.',
 'intermediate', 'true_false', 'Consider what a connector replaces compared to manually exporting a report.', 23),
((select id from public.modules where slug='tool-use'), 'hr',
 'An HRIS connector now lets Claude draft communications referencing specific employees'' leave balances it reads directly. What''s the key concern?',
 '["Reviewing what sensitive data is being read and shared, since privacy is at stake", "There''s no concern since the data is accurate", "The connector should read as much data as possible for completeness", "Only IT needs to worry about this, not HR"]'::jsonb,
 0, 'Because this touches sensitive personal data automatically, an overly broad or incorrect pull is a real privacy risk.',
 'advanced', 'scenario', 'Think about what kind of data is involved here and what happens if too much of it gets pulled or shared.', 24),
((select id from public.modules where slug='tool-use'), 'finance',
 'How might web search help someone doing finance work with Claude?',
 '["Looking up a current exchange rate or recent market move", "Automatically approving a transaction", "Permanently deleting financial records", "Changing the company''s accounting method"]'::jsonb,
 0, 'Live, constantly-changing data like exchange rates is exactly what web search is good for.',
 'beginner', 'mcq', 'Think about what kind of financial data changes minute to minute.', 25),
((select id from public.modules where slug='tool-use'), 'finance',
 'A connector to your accounting software lets Claude read current data directly, instead of relying on a manually pasted export.',
 '["True", "False"]'::jsonb,
 0, 'That''s the core benefit of a connector — direct, current access instead of a possibly stale manual export.',
 'intermediate', 'true_false', 'Consider what a connector replaces compared to manually exporting and pasting a report.', 26),
((select id from public.modules where slug='tool-use'), 'finance',
 'A connector now pulls live figures from your accounting system directly into a forecast draft. What should you do before trusting it?',
 '["Spot-check the pulled figures against the source", "Publish the forecast immediately with no review", "Disconnect all connectors permanently", "Assume the connector can never make a mistake"]'::jsonb,
 0, 'A connector reading the wrong period or account could silently skew numbers that look plausible at a glance, so spot-checking matters.',
 'advanced', 'scenario', 'Think about what could go wrong if the connector reads the wrong period or account without you noticing.', 27);

-- ---- workflows ----
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, difficulty, kind, hint, order_index) values
((select id from public.modules where slug='workflows'), null,
 'What is a "workflow" when working with Claude?',
 '["A sequence of connected steps that together accomplish a larger task", "A single one-word command", "A setting that changes Claude''s response length", "A type of file format"]'::jsonb,
 0, 'A workflow chains multiple steps together, rather than relying on one single request to do everything.',
 'beginner', 'mcq', 'Think about what "sequence of steps" implies versus a single request.', 1),
((select id from public.modules where slug='workflows'), null,
 'Breaking a big task into smaller steps makes it easier to catch and fix problems early.',
 '["True", "False"]'::jsonb,
 0, 'Smaller steps let you review and correct along the way, rather than discovering a problem buried in one huge final output.',
 'beginner', 'true_false', 'Consider what happens when you can check work partway through versus only at the very end.', 2),
((select id from public.modules where slug='workflows'), null,
 'You need Claude to research a topic, outline it, then write a full report. What''s the best approach?',
 '["Treat it as connected steps, reviewing each before moving to the next", "Ask for everything at once in a single giant request", "Skip the research step entirely to save time", "Only ask for the final report with no other steps"]'::jsonb,
 0, 'Splitting into reviewed steps catches problems early, before they carry through the whole chain.',
 'beginner', 'scenario', 'Think about what happens if an early step has an error and nobody notices until the end.', 3),
((select id from public.modules where slug='workflows'), null,
 'A workflow you''ve refined once and can reuse for the same type of task going forward is called a _____ prompt chain.',
 '["repeatable", "one-time", "hidden", "broken"]'::jsonb,
 0, 'A repeatable prompt chain is a sequence you can reuse, swapping in new details each time.',
 'intermediate', 'fill_blank', 'Think of a word meaning "can be used again."', 4),
((select id from public.modules where slug='workflows'), null,
 'Why does reviewing Claude''s output at each step of a workflow matter more than reviewing only the final result?',
 '["An early mistake can compound into every later step that builds on it", "Reviewing at each step takes less total time", "Claude cannot make mistakes in early steps", "Final results are always correct regardless of earlier steps"]'::jsonb,
 0, 'If an error goes unnoticed early on, every step that builds on it inherits that same error.',
 'intermediate', 'mcq', 'Think about what happens to a mistake made in step one by the time you reach step five.', 5),
((select id from public.modules where slug='workflows'), null,
 'Once you build a workflow for one recurring task, you have to reinvent it completely from scratch for every similar new task.',
 '["True", "False"]'::jsonb,
 1, 'A well-built workflow is meant to be reused, with new details swapped in — not rebuilt from zero each time.',
 'intermediate', 'true_false', 'Consider what "repeatable" is meant to save you from doing.', 6),
((select id from public.modules where slug='workflows'), null,
 'How should you decide where to split a multi-step workflow into separate steps?',
 '["Split at points where you''d actually want to review or could redirect the work", "Split after every single sentence, no matter how small", "Never split anything \u2014 always use one giant request", "Split randomly with no particular reasoning"]'::jsonb,
 0, 'Splitting at meaningful review or decision points adds real value — splitting everywhere just adds friction without benefit.',
 'advanced', 'scenario', 'Think about what makes a step boundary actually useful versus just extra overhead.', 7),
((select id from public.modules where slug='workflows'), null,
 'Combining several Claude capabilities in sequence — research, drafting, and formatting — into one coherent process is called an _____ workflow.',
 '["end-to-end", "isolated", "one-shot", "disconnected"]'::jsonb,
 0, '"End-to-end" describes a workflow that covers the whole task from start to finish as one connected process.',
 'advanced', 'fill_blank', 'Think of a phrase describing something that spans the whole process, start to finish.', 8),
((select id from public.modules where slug='workflows'), null,
 'A workflow built for one recurring task needs two of its five steps modified for a similar but different task. What''s the best approach?',
 '["Reuse the three steps that transfer directly and only rework the two that need to change", "Build an entirely new workflow from scratch every time", "Refuse to adapt it and use the original workflow unchanged", "Discard workflows entirely and go back to single giant prompts"]'::jsonb,
 0, 'Most of a workflow''s value usually carries over — targeted adaptation is more efficient than rebuilding from zero.',
 'advanced', 'mcq', 'Think about how much of the original workflow actually needs to change versus stays useful as-is.', 9),
((select id from public.modules where slug='workflows'), 'recruitment',
 'What might a recruitment workflow with Claude look like end-to-end?',
 '["Draft the job posting, then outreach messages, then interview questions", "One single request asking for everything with no structure", "Only ever writing a job posting and nothing else", "Randomly generated unrelated content"]'::jsonb,
 0, 'Chaining connected steps builds a complete hiring kit, rather than relying on a single giant request.',
 'beginner', 'mcq', 'Think about the natural sequence of tasks in filling a role.', 10),
((select id from public.modules where slug='workflows'), 'recruitment',
 'When screening resumes then drafting outreach then prepping interview questions, it''s best to review the shortlist before drafting outreach for it.',
 '["True", "False"]'::jsonb,
 0, 'Reviewing the shortlist first catches issues before outreach is drafted for the wrong set of candidates.',
 'intermediate', 'true_false', 'Consider what happens if the outreach step builds on an unreviewed shortlist.', 11),
((select id from public.modules where slug='workflows'), 'recruitment',
 'A resume-screening-to-outreach workflow works well, but a new role needs different screening criteria and outreach tone. What''s the best approach?',
 '["Reuse the overall structure, swapping in new criteria and tone at the relevant steps", "Build a completely new workflow from scratch", "Refuse to change anything and use the old criteria anyway", "Skip the screening step entirely for this role"]'::jsonb,
 0, 'The workflow''s shape still holds even though specific steps need real changes — full rebuilds aren''t necessary.',
 'advanced', 'scenario', 'Think about how much of the original sequence still applies versus what specifically needs updating.', 12),
((select id from public.modules where slug='workflows'), 'marketing',
 'What could a content-creation workflow with Claude include end-to-end?',
 '["Research the topic, draft an outline, write the post, then adapt it into social captions", "A single request with no distinct steps", "Only writing social captions and nothing else", "Randomly picking a topic with no research"]'::jsonb,
 0, 'This is a chain of connected steps that together build a complete content package.',
 'beginner', 'mcq', 'Think about the natural sequence from idea to finished, multi-format content.', 13),
((select id from public.modules where slug='workflows'), 'marketing',
 'Checking the outline before asking Claude to write the full post from it can save you from a full draft built on the wrong foundation.',
 '["True", "False"]'::jsonb,
 0, 'Catching an issue with the outline early avoids that issue compounding into the entire draft.',
 'intermediate', 'true_false', 'Consider what happens if the outline''s angle is wrong and it isn''t caught until after the draft is written.', 14),
((select id from public.modules where slug='workflows'), 'marketing',
 'Your blog-post workflow works well, but this campaign needs a video script instead of a blog post at the drafting step. What''s the best approach?',
 '["Keep the research and outline steps as-is, and swap only the drafting step''s output format", "Rebuild the entire workflow from scratch for video", "Skip research and outlining entirely for video content", "Refuse to adapt the workflow and use the blog-post version anyway"]'::jsonb,
 0, 'Most of the workflow''s value is in the earlier steps, which don''t need to change just because the final format does.',
 'advanced', 'scenario', 'Think about which steps actually depend on the final output format and which don''t.', 15),
((select id from public.modules where slug='workflows'), 'sales',
 'What could a deal-prep workflow with Claude look like end-to-end?',
 '["Research the prospect, draft talking points, then prepare a follow-up email", "One giant request covering the entire deal with no steps", "Only researching the prospect and nothing else", "Randomly generated unrelated content"]'::jsonb,
 0, 'This chain of connected steps builds a complete, call-ready package.',
 'beginner', 'mcq', 'Think about the natural sequence of preparing for and following up on a sales call.', 16),
((select id from public.modules where slug='workflows'), 'sales',
 'If a pitch draft and objection-handling notes both build on prospect research, it''s worth confirming the research is accurate before moving forward.',
 '["True", "False"]'::jsonb,
 0, 'An error in the research step would carry through into everything built on top of it.',
 'intermediate', 'true_false', 'Consider what happens to later steps if the earliest step contains a mistake.', 17),
((select id from public.modules where slug='workflows'), 'sales',
 'Your outreach workflow works for cold prospects, but warm referrals need a different opening in the pitch step. What''s the best approach?',
 '["Keep the research and follow-up steps unchanged, and only adjust the pitch step''s opening", "Rebuild the entire workflow from scratch for referrals", "Skip the pitch step entirely for referrals", "Refuse to adapt and use the cold-outreach pitch anyway"]'::jsonb,
 0, 'Most of the sequence transfers directly — only the piece that actually differs needs to change.',
 'advanced', 'scenario', 'Think about which step is actually different for a referral versus a cold prospect.', 18),
((select id from public.modules where slug='workflows'), 'engineering',
 'What could a code-review workflow with Claude include end-to-end?',
 '["Summarize the diff, flag potential issues, then draft review comments", "A single request to \"review this\" with no further structure", "Only flagging issues with no summary or comments", "Randomly picking lines of code to comment on"]'::jsonb,
 0, 'This chain of steps builds a complete, useful review rather than a vague single pass.',
 'beginner', 'mcq', 'Think about the natural sequence a careful human reviewer would follow.', 19),
((select id from public.modules where slug='workflows'), 'engineering',
 'Confirming Claude''s bug diagnosis is correct before asking it to draft the fix helps catch an issue before it compounds into the next step.',
 '["True", "False"]'::jsonb,
 0, 'If the diagnosis is wrong, a fix built on it will likely be wrong too — checking first avoids that compounding.',
 'intermediate', 'true_false', 'Consider what happens to the fix if the diagnosis it''s based on is incorrect.', 20),
((select id from public.modules where slug='workflows'), 'engineering',
 'Your bug-triage workflow works well for backend bugs, but frontend bugs need a different reproduction step. What''s the best approach?',
 '["Reuse the diagnose and draft-fix steps as-is, and only rework the reproduction step", "Rebuild the entire workflow from scratch for frontend bugs", "Skip the reproduction step entirely for frontend bugs", "Refuse to adapt and use the backend reproduction step anyway"]'::jsonb,
 0, 'The overall shape of the workflow still holds — only the step that genuinely differs needs to change.',
 'advanced', 'scenario', 'Think about which step actually depends on whether the bug is frontend or backend.', 21),
((select id from public.modules where slug='workflows'), 'hr',
 'What could an onboarding-content workflow with Claude look like end-to-end?',
 '["Draft the welcome email, then the checklist, then FAQ answers", "One massive request covering all onboarding content at once", "Only writing FAQ answers and nothing else", "Randomly generated unrelated content"]'::jsonb,
 0, 'This sequence of connected pieces builds a complete onboarding package.',
 'beginner', 'mcq', 'Think about the natural sequence of documents a new hire receives.', 22),
((select id from public.modules where slug='workflows'), 'hr',
 'Reviewing the welcome email''s tone before extending it across the checklist helps prevent a tone problem from repeating throughout the sequence.',
 '["True", "False"]'::jsonb,
 0, 'Catching a tone issue in the first document prevents it from being carried into every later document in the chain.',
 'intermediate', 'true_false', 'Consider what happens if the tone is off and it isn''t caught until after every document is written.', 23),
((select id from public.modules where slug='workflows'), 'hr',
 'Your onboarding workflow works well, but a new remote-hire track needs a different checklist step. What''s the best approach?',
 '["Keep the welcome email and FAQ steps as they are, and rework only the checklist step", "Rebuild the entire workflow from scratch for remote hires", "Skip the checklist step entirely for remote hires", "Refuse to adapt and use the in-office checklist anyway"]'::jsonb,
 0, 'Most of the workflow still applies — only the step that genuinely differs for remote hires needs to change.',
 'advanced', 'scenario', 'Think about which step actually depends on whether the hire is remote or in-office.', 24),
((select id from public.modules where slug='workflows'), 'finance',
 'What could a monthly reporting workflow with Claude include end-to-end?',
 '["Summarize the numbers, draft variance commentary, then format the executive summary", "One single request covering the entire report with no steps", "Only formatting the executive summary with no other steps", "Randomly generated unrelated commentary"]'::jsonb,
 0, 'This chain of connected steps builds the finished report piece by piece.',
 'beginner', 'mcq', 'Think about the natural sequence from raw numbers to a polished final report.', 25),
((select id from public.modules where slug='workflows'), 'finance',
 'Since variance commentary and the executive summary both depend on the number summary, it''s worth checking that summary for accuracy first.',
 '["True", "False"]'::jsonb,
 0, 'An early error in the number summary would carry through into everything built on top of it.',
 'intermediate', 'true_false', 'Consider what happens to later steps if the earliest step contains an inaccurate figure.', 26),
((select id from public.modules where slug='workflows'), 'finance',
 'Your close-reporting workflow works well, but the board version needs a different executive-summary step. What''s the best approach?',
 '["Keep the summarize and variance-commentary steps unchanged, and adapt only the exec-summary step", "Rebuild the entire workflow from scratch for the board version", "Skip the summarize step entirely for the board version", "Refuse to adapt and use the original exec summary anyway"]'::jsonb,
 0, 'Most of the workflow transfers directly — only the piece that genuinely needs to differ for the board audience should change.',
 'advanced', 'scenario', 'Think about which step actually depends on the specific audience receiving the report.', 27);

-- ===========================================================================
-- BADGES
-- ===========================================================================
insert into public.badges (slug, name, description, icon) values
('first-steps',    'First Steps',    'Complete your very first module and start your Claude journey.', '🌱'),
('prompt-pro',     'Prompt Pro',     'Ace the Prompting Fundamentals quiz and prove your prompting chops.', '✍️'),
('halfway-hero',   'Halfway Hero',   'Reach 50% course completion — you are officially over the hump.', '⚡'),
('perfect-score',  'Perfect Score',  'Get every question right on a module quiz.', '💯'),
('claude-master',  'Claude Master',  'Complete every module and master the full surface of Claude.', '🧠'),
('streak-starter', 'Streak Starter', 'Complete two modules and get your momentum going.', '🔥');

commit;
