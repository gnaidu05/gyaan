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
-- FLASHCARDS  (4 generic + 6 profession = 10 per deck)
-- ===========================================================================

-- ---- chat-basics ----------------------------------------------------------
insert into public.flashcards (deck_id, profession, front, back, order_index) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'What is the "context window"?', 'The full conversation history — every message you and Claude have exchanged in that chat — that Claude reads each time before replying. It is how Claude "remembers" earlier turns.', 1),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'Does Claude remember other chats?', 'No. Each new conversation starts fresh with no memory of your other threads. Keep a related task in one chat so the context stays intact.', 2),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'Why iterate instead of restarting?', 'Follow-ups build on everything already in the conversation, so you can refine ("shorter", "more formal") without re-explaining. The best results come from iteration, not the first message.', 3),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), null,
 'One quick way to improve any response?', 'Give Claude a role and a goal — who it is helping, for what audience, and what "good" looks like. Claude adapts tone, depth, and format to the situation you describe.', 4),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'recruitment',
 'As a recruiter, how do you refine a candidate message without retyping the role?', 'Keep refining in the same thread — Claude still holds the role, seniority, and company context, so "make it warmer" or "shorten it" just works.', 5),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'marketing',
 'As a marketer brainstorming taglines, why stay in one chat?', 'Because Claude keeps every earlier idea in context, so each new batch reacts to your feedback and builds on the directions you liked instead of starting over.', 6),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'sales',
 'After a discovery call, what should you paste into Claude?', 'Your actual raw notes. Relevant detail — the real quotes and pains — lets Claude produce a grounded recap and a personalized follow-up rather than a generic email.', 7),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'engineering',
 'How does chat context help when debugging a stack trace?', 'Claude remembers what you have already ruled out, so as you check each hypothesis it reasons like a pair-programmer tracking the whole investigation, not isolated questions.', 8),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'hr',
 'Drafting a sensitive announcement — how do you find the right tone?', 'Ask for a first draft, then adjust in the same thread ("less corporate", "more empathetic"). Claude keeps the message intact while you tune the tone.', 9),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='chat-basics')), 'finance',
 'Why paste the actual variance figures rather than describe them?', 'Claude reasons from what you give it. The real line-item breakdown lets it pinpoint what drove a variance and draft an accurate explanation instead of guessing.', 10);

-- ---- prompting ------------------------------------------------------------
insert into public.flashcards (deck_id, profession, front, back, order_index) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'The single biggest prompting upgrade?', 'Be specific about the outcome — state length, audience, tone, and format. Specific prompts get useful answers — vague prompts get generic ones.', 1),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'What is "few-shot" prompting?', 'Showing Claude one or more examples of the style or format you want. A single good example often teaches more than a paragraph of description.', 2),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'When an answer misses, what usually fixes it?', 'Adding the missing context or constraint — not just rephrasing. Nine times out of ten the gap is information Claude did not have.', 3),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), null,
 'Why assign Claude a role in a prompt?', 'A role primer ("act as a skeptical CFO") shapes the whole response — its perspective, tone, and what it emphasizes.', 4),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'recruitment',
 'What makes a job-description prompt produce a great JD?', 'Concrete role specifics (level, stack, salary band, reporting line, tone) plus an example JD you admire, so Claude matches your structure and voice.', 5),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'marketing',
 'How do you keep ad copy on-brand in a prompt?', 'Name the audience, spell out voice rules and banned words, set hard constraints (like character limits), and include a proven headline as a style example.', 6),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'sales',
 'What turns a generic cold email into a specific one?', 'A trigger event, a single clear value prop and ask, length limits, and a past email that actually booked meetings as the style model.', 7),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'engineering',
 'How do you prompt for code you can use as-is?', 'Specify language, function signature, inputs, edge cases, error behavior, and constraints (no external libs), then ask Claude to list the edge cases it handled.', 8),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'hr',
 'How do you get interview questions you can actually score?', 'Name the competencies to assess and ask for a scoring rubric describing weak, average, and strong answers — not just a list of questions.', 9),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='prompting')), 'finance',
 'How do you ground a modeling answer in your numbers?', 'State your assumptions explicitly and ask for cell-by-cell formulas plus where to sanity-check, so the output is precise and auditable.', 10);

-- ---- projects -------------------------------------------------------------
insert into public.flashcards (deck_id, profession, front, back, order_index) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'What is a Project in Claude?', 'A dedicated workspace bundling custom instructions and reference files, so every conversation started inside it already knows your context.', 1),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'What are custom instructions?', 'Standing orders that apply to every chat in a Project — your tone, audience, and rules — set once instead of repeated in every message.', 2),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'What is Project knowledge?', 'Documents you upload once (style guides, specs, policies, templates) that Claude can draw on in any chat in that Project, grounding answers in your material.', 3),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), null,
 'Do chats in a Project share conversation history?', 'No. A Project shares knowledge and instructions across chats, but each individual chat still has its own separate context.', 4),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'recruitment',
 'How does a Project keep outreach on employer-brand?', 'Custom instructions carry your brand voice and rules, and uploaded EVP and benefits docs ground every draft — so the whole team sounds consistent without re-briefing.', 5),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'marketing',
 'Why put your style guide in a Project?', 'So every asset any team member generates follows the same voice, banned words, and formatting — the brand system lives in the Project, not one person''s head.', 6),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'sales',
 'How do Projects stop reps inventing pricing?', 'Custom instructions tell Claude to use only uploaded materials for facts and pricing, so answers are grounded in approved one-pagers and the real price list.', 7),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'engineering',
 'What does a codebase Project cut down on?', 'Review churn — Claude drafts code matching your uploaded conventions and architecture docs, so new hires ramp faster and style nits shrink.', 8),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'hr',
 'How does a policy Project handle an unknown question?', 'You instruct Claude to answer only from uploaded policies and to say "not covered, contact X" rather than guess — keeping answers accurate and safe.', 9),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='projects')), 'finance',
 'How does a finance Project keep coding consistent?', 'It answers from your accounting policies and chart of accounts with citations, and flags genuinely ambiguous treatments for review instead of deciding.', 10);

-- ---- artifacts ------------------------------------------------------------
insert into public.flashcards (deck_id, profession, front, back, order_index) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'What is an Artifact?', 'A standalone piece of content — document, table, chart, code, or small app — that opens in its own panel beside the chat, so you can keep, edit, and share it.', 1),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'How do you change an Artifact?', 'Describe the change in plain language ("make the header blue", "add a column") and Claude updates the same Artifact in place — you iterate, not copy-paste.', 2),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'Can Claude build working software as an Artifact?', 'Yes — it can write real HTML/JavaScript that runs in the panel, so calculators, dashboards, and forms actually work and you refine them by describing changes.', 3),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), null,
 'What makes something a good Artifact candidate?', 'Content you want to keep, edit, or share: polished documents, comparison tables, interactive tools, and charts — rather than a quick answer in the chat.', 4),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'recruitment',
 'What is a strong Artifact for a hiring loop?', 'A shared interview scorecard — competencies, per-interviewer notes, scores, and a hire recommendation — that you refine live and export for every interviewer.', 5),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'marketing',
 'How can an Artifact beat a slide in a campaign review?', 'Build a clickable landing-page mockup as an Artifact, so stakeholders react to something real and you tweak the hero or CTA copy live in the meeting.', 6),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'sales',
 'What Artifact makes your value concrete to a prospect?', 'An interactive ROI calculator the prospect plugs their own numbers into — savings and payback update live, far more persuasive than a static PDF.', 7),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'engineering',
 'How do Artifacts speed up validating a UI idea?', 'Claude builds a runnable component you can click through immediately and refine by describing behavior — no branch or dev server just to show what you mean.', 8),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'hr',
 'What reusable Artifact helps onboarding?', 'A new-hire checklist grouped by phase (Before Day 1, Week 1, 30/90 days) with owners and checkboxes — build once, reuse for every hire.', 9),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='artifacts')), 'finance',
 'How can an Artifact make budget scenarios clearer?', 'An interactive dashboard where changing growth, headcount, or spend updates revenue, cost, and margin live — leadership sees assumptions flow to the bottom line.', 10);

-- ---- tool-use -------------------------------------------------------------
insert into public.flashcards (deck_id, profession, front, back, order_index) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'What does web search let Claude do?', 'Look things up in real time and answer with up-to-date facts and links, instead of relying only on what it learned during training.', 1),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'What is a connector?', 'A link between Claude and your own tools (Google Drive, Gmail, GitHub, Slack, etc.) so it can read or act on your files and systems within the permissions you grant.', 2),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'What is MCP (Model Context Protocol)?', 'The open standard that lets teams plug their own internal systems into Claude, making tool use extensible beyond the built-in connectors.', 3),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), null,
 'What is your responsibility when Claude uses tools?', 'Verify anything high-stakes by clicking the sources Claude cites, and grant only the access a task actually needs. Tools reduce guesswork but do not remove your judgment.', 4),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'recruitment',
 'How do tools sharpen an intake call prep?', 'Web search pulls current salary benchmarks and recent company news (funding, layoffs) with links, so your outreach and intake are informed, not guesswork.', 5),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'marketing',
 'Why use web search for campaign planning?', 'Competitor positioning and trending angles change constantly — search grounds your strategy in what is happening now, with citations, rather than last year''s knowledge.', 6),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'sales',
 'How do search plus a connector build a pre-call brief?', 'Search pulls the account''s recent news while a Drive connector retrieves your last meeting notes — Claude merges them so you open the call current and continuous.', 7),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'engineering',
 'Why connect Claude to your repo instead of pasting a snippet?', 'It can read the real files and tests through the connector and cross-check current API docs via search, grounding analysis in your actual code rather than assumptions.', 8),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'hr',
 'How do tools help answer a tricky leave question?', 'A connector reads your internal policy while search checks current statutory rules, surfacing any gap between the two with sources — on-policy and legally current.', 9),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='tool-use')), 'finance',
 'Why use search when updating a forecast?', 'Rates, FX, and competitors'' latest reported figures must be accurate as of today — search retrieves them with citations so assumptions rest on verifiable current data.', 10);

-- ---- workflows ------------------------------------------------------------
insert into public.flashcards (deck_id, profession, front, back, order_index) values
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'What is a Claude "workflow"?', 'A repeatable sequence where each step''s output feeds the next — research, outline, draft, refine, format — run as one steered conversation instead of one-off asks.', 1),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'How do Projects, Artifacts, and tools fit a workflow?', 'A Project loads your context automatically, tools fetch live data for steps that need it, and Artifacts hold the deliverables you keep or share.', 2),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'How do you make a workflow repeatable?', 'Save the sequence of prompts that worked. Next time it is a template you fill in, not a blank page, and good prompt chains compound over time.', 3),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), null,
 'What is the human''s role in a workflow?', 'To decide, verify, and own the result. Claude drafts, accelerates, and organizes — you keep judgment in the loop and remove the busywork around it.', 4),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'recruitment',
 'What does a hiring-kit workflow chain together?', 'JD, then screening rubric, then outreach variants, then an interview guide — each approved step feeding the next, reusable for the next requisition.', 5),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'marketing',
 'What does a content-repurposing workflow produce?', 'One brief becomes a blog post, then LinkedIn posts, an email, and ad variants — a coordinated, on-voice package from a single guided chain.', 6),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'sales',
 'What are the steps of a prospecting workflow?', 'Research the account, personalize the first email from the hook, build a follow-up sequence, and write a clean CRM note — run identically across your list.', 7),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'engineering',
 'What does a ticket-to-PR workflow look like?', 'Clarify the requirement, propose a design with trade-offs, implement to your conventions, write tests, and draft the PR description — reviewing each stage.', 8),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'hr',
 'What does an onboarding workflow orchestrate?', 'The checklist by phase and owner, welcome comms and first-week schedule, a 30-day check-in agenda, and a manager briefing — so nothing slips for a new hire.', 9),
((select id from public.flashcard_decks where module_id=(select id from public.modules where slug='workflows')), 'finance',
 'What does a month-end close workflow chain?', 'Flag accounts that moved sharply, draft variance explanations to verify, build the management summary, and list follow-ups for department heads — repeatable monthly.', 10);

-- ===========================================================================
-- QUIZ QUESTIONS  (4 generic + 6 profession = 10 per module)
-- ===========================================================================

-- ---- chat-basics ----------------------------------------------------------
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, order_index) values
((select id from public.modules where slug='chat-basics'), null,
 'What does the "context window" refer to?',
 '["The conversation history Claude reads before each reply","A pop-up settings menu","The maximum file size you can upload","Claude''s permanent memory of all your chats"]'::jsonb,
 0, 'The context window is the running conversation history Claude reads each turn — how it remembers what was said earlier in that chat.', 1),
((select id from public.modules where slug='chat-basics'), null,
 'You start a brand-new chat. What does Claude know about your previous conversations?',
 '["Everything from the last 24 hours","Nothing — each new chat starts fresh","Only the last message you sent","All chats from the same day"]'::jsonb,
 1, 'Claude has no memory across separate chats — a new conversation begins with a clean slate.', 2),
((select id from public.modules where slug='chat-basics'), null,
 'The best way to improve a response you are not happy with is usually to:',
 '["Start over in a new chat every time","Send the exact same message again","Refine with a follow-up in the same thread","Make the message as short as possible"]'::jsonb,
 2, 'Follow-ups build on the existing context, so iterating in the same thread refines the result without re-explaining.', 3),
((select id from public.modules where slug='chat-basics'), null,
 'Which quick addition most improves Claude''s response?',
 '["Typing in all capital letters","Giving Claude a role, audience, and goal","Adding lots of emoji","Keeping every request under five words"]'::jsonb,
 1, 'Telling Claude who it is helping, for whom, and what good looks like lets it adapt tone, depth, and format.', 4),
((select id from public.modules where slug='chat-basics'), 'recruitment',
 'You drafted candidate outreach but want it warmer. What is the efficient move?',
 '["Open a new chat and re-describe the whole role","Say ''make it warmer'' in the same thread","Paste the job description again first","Ask Claude to forget the previous draft"]'::jsonb,
 1, 'The thread still holds the role and context, so a simple follow-up like "make it warmer" is enough.', 5),
((select id from public.modules where slug='chat-basics'), 'marketing',
 'While brainstorming taglines, why keep reacting inside one conversation?',
 '["It uses fewer words overall","Claude keeps earlier ideas in context and builds on your feedback","New chats produce funnier taglines","It hides the ideas you rejected"]'::jsonb,
 1, 'Staying in one chat lets each new batch react to your feedback and build on the directions you liked.', 6),
((select id from public.modules where slug='chat-basics'), 'sales',
 'To get a strong post-call recap and follow-up email, you should:',
 '["Describe the call from memory in one line","Paste your actual raw notes from the call","Ask Claude to invent likely talking points","Only give the prospect''s company name"]'::jsonb,
 1, 'Claude reasons from what you provide, so pasting the real notes yields a grounded, personalized follow-up.', 7),
((select id from public.modules where slug='chat-basics'), 'engineering',
 'Why is a chat thread useful while debugging a stack trace step by step?',
 '["It compiles your code automatically","Claude remembers what you have already ruled out","It hides the error message","It restarts the investigation each reply"]'::jsonb,
 1, 'The retained context lets Claude reason like a pair-programmer tracking everything you have already tried.', 8),
((select id from public.modules where slug='chat-basics'), 'hr',
 'You need the right tone for a sensitive policy announcement. Best approach?',
 '["Publish Claude''s first draft immediately","Draft it, then tune tone with follow-ups in the same thread","Write it entirely yourself to avoid context","Ask for ten unrelated drafts at once"]'::jsonb,
 1, 'Iterating on tone ("less corporate", "more empathetic") in the same thread keeps the message intact while you refine it.', 9),
((select id from public.modules where slug='chat-basics'), 'finance',
 'To explain an 18% budget variance, what should you give Claude?',
 '["Just the final over-budget percentage","The actual line-item breakdown of the figures","Only last year''s annual report","A request to guess the cause"]'::jsonb,
 1, 'The real line-item detail lets Claude pinpoint what drove the variance instead of guessing.', 10);

-- ---- prompting ------------------------------------------------------------
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, order_index) values
((select id from public.modules where slug='prompting'), null,
 'Which prompt is most likely to get a useful result?',
 '["Write about our product","Write a 120-word LinkedIn post for ops managers, friendly, ending in a question","Make it good","Tell me something about marketing"]'::jsonb,
 1, 'Specifying length, audience, tone, and format gives Claude clear direction to follow.', 1),
((select id from public.modules where slug='prompting'), null,
 'What is "few-shot" prompting?',
 '["Sending many prompts quickly","Including one or more examples of the style you want","Limiting yourself to a few words","Asking Claude to answer in a few seconds"]'::jsonb,
 1, 'Few-shot prompting means showing example(s) — one good example often teaches more than a long description.', 2),
((select id from public.modules where slug='prompting'), null,
 'An answer misses the mark. What most reliably fixes it?',
 '["Rephrasing the same request differently","Adding the missing context or constraint","Sending it again unchanged","Making the prompt shorter"]'::jsonb,
 1, 'Usually the gap is information Claude did not have — adding the missing context or constraint fixes it.', 3),
((select id from public.modules where slug='prompting'), null,
 'Why assign Claude a role like "act as a skeptical CFO"?',
 '["It makes responses longer","It shapes the perspective, tone, and emphasis of the whole answer","It disables web search","It guarantees a shorter reply"]'::jsonb,
 1, 'A role primer frames how Claude approaches the task, changing perspective and emphasis.', 4),
((select id from public.modules where slug='prompting'), 'recruitment',
 'Which extra input most improves a job-description prompt?',
 '["The word ''rockstar''","Role specifics plus an example JD you admire","A demand for maximum length","Only the job title"]'::jsonb,
 1, 'Concrete specifics and a style example let Claude match your structure and voice.', 5),
((select id from public.modules where slug='prompting'), 'marketing',
 'To keep ad copy on-brand, your prompt should include:',
 '["Only the product name","Audience, voice rules, banned words, a length limit, and a proven example","A request to be as creative as possible","The full company history"]'::jsonb,
 1, 'Naming the audience, voice rules, constraints, and a proven example yields usable, on-brand variations.', 6),
((select id from public.modules where slug='prompting'), 'sales',
 'What most improves a cold-email prompt?',
 '["A trigger event, one clear ask, a length limit, and a winning example","Listing every product feature","A very long greeting","Ten different calls to action"]'::jsonb,
 0, 'Specificity — a trigger, a single ask, limits, and a proven model — makes the email personalized and tight.', 7),
((select id from public.modules where slug='prompting'), 'engineering',
 'For code you can use as-is, your prompt should specify:',
 '["Only the language","Signature, inputs, edge cases, error behavior, and constraints","Just ''write a function''","The color of your editor theme"]'::jsonb,
 1, 'A precise spec covering inputs, edge cases, and constraints yields code that matches your requirements.', 8),
((select id from public.modules where slug='prompting'), 'hr',
 'To get interview questions you can score consistently, ask for:',
 '["A long list of trivia questions","Named competencies plus a rubric for weak/average/strong answers","Questions copied from a website","Only yes/no questions"]'::jsonb,
 1, 'Naming competencies and requesting a scoring rubric produces a structured, defensible interview guide.', 9),
((select id from public.modules where slug='prompting'), 'finance',
 'To ground a modeling answer in your numbers, you should:',
 '["Ask for a general overview only","State your assumptions and request cell-by-cell formulas","Avoid giving any figures","Ask Claude to pick random assumptions"]'::jsonb,
 1, 'Explicit assumptions plus a request for cell-level formulas make the output precise and auditable.', 10);

-- ---- projects -------------------------------------------------------------
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, order_index) values
((select id from public.modules where slug='projects'), null,
 'What is a Project in Claude?',
 '["A single one-off chat","A workspace bundling custom instructions and reference files reused across chats","A paid subscription tier","A way to delete your history"]'::jsonb,
 1, 'A Project is a dedicated workspace whose instructions and knowledge apply to every conversation inside it.', 1),
((select id from public.modules where slug='projects'), null,
 'What do "custom instructions" do?',
 '["Apply standing rules to every chat in the Project","Only affect the first message","Change Claude''s pricing","Delete uploaded files automatically"]'::jsonb,
 0, 'Custom instructions are standing orders — tone, audience, rules — applied to every chat in the Project.', 2),
((select id from public.modules where slug='projects'), null,
 'What is Project knowledge?',
 '["Claude''s general training data","Documents you upload once and reuse across the Project''s chats","A public library of templates","Your browser history"]'::jsonb,
 1, 'Project knowledge is your uploaded reference material that Claude can draw on in any chat in the Project.', 3),
((select id from public.modules where slug='projects'), null,
 'Do separate chats inside one Project share their conversation history?',
 '["Yes, all chats merge into one","No — they share knowledge and instructions, but each chat has its own context","Only if they are open at the same time","Only the first two chats do"]'::jsonb,
 1, 'A Project shares knowledge and instructions, but each individual chat keeps its own separate context.', 4),
((select id from public.modules where slug='projects'), 'recruitment',
 'How does a Project keep the whole team''s outreach on employer-brand?',
 '["By limiting message length","Instructions carry brand voice and uploaded EVP/benefits docs ground every draft","By hiding older candidates","By auto-sending messages"]'::jsonb,
 1, 'Brand voice in the instructions plus uploaded EVP and benefits docs make drafts consistent without re-briefing.', 5),
((select id from public.modules where slug='projects'), 'marketing',
 'Why put your style guide into a brand Project?',
 '["To make it read-only","So every asset any teammate generates follows the same voice and rules","To translate it automatically","To reduce the file count"]'::jsonb,
 1, 'The brand system living in the Project keeps everyone''s output consistent instead of relying on one person.', 6),
((select id from public.modules where slug='projects'), 'sales',
 'How does a sales Project stop reps citing wrong pricing?',
 '["It blocks the pricing page","Instructions tell Claude to use only uploaded materials for facts and pricing","It emails the CFO for approval","It rounds all prices up"]'::jsonb,
 1, 'Restricting Claude to approved uploaded materials means answers use the real price list, not invented figures.', 7),
((select id from public.modules where slug='projects'), 'engineering',
 'What does a codebase-conventions Project most reduce?',
 '["Compile time","Review churn over style and pattern nits","The need for tests","Server costs"]'::jsonb,
 1, 'Code drafted to your uploaded conventions cuts review churn and helps new hires follow your standards.', 8),
((select id from public.modules where slug='projects'), 'hr',
 'In a policy Project, what should Claude do when a question is not covered?',
 '["Guess a reasonable answer","Say it is not covered and suggest who to contact","Refuse to respond at all","Invent a new policy"]'::jsonb,
 1, 'Instructing Claude to flag gaps rather than guess keeps answers accurate and low-risk.', 9),
((select id from public.modules where slug='projects'), 'finance',
 'How does a finance Project handle an ambiguous accounting treatment?',
 '["Picks whichever is cheaper","Flags it for review instead of deciding, citing the policy","Ignores the question","Averages the two options"]'::jsonb,
 1, 'Grounding answers in policy with citations and flagging ambiguity for review keeps the books consistent.', 10);

-- ---- artifacts ------------------------------------------------------------
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, order_index) values
((select id from public.modules where slug='artifacts'), null,
 'What is an Artifact?',
 '["A hidden system prompt","A standalone piece of content in its own panel you can keep, edit, and share","A type of connector","A billing record"]'::jsonb,
 1, 'An Artifact is standalone content — a doc, table, chart, or app — that opens beside the chat for you to keep and edit.', 1),
((select id from public.modules where slug='artifacts'), null,
 'How do you change an existing Artifact?',
 '["Delete it and start over each time","Describe the change and Claude updates it in place","Edit the raw database","Copy it into a new chat"]'::jsonb,
 1, 'You iterate by describing changes in plain language — Claude updates the same Artifact rather than you copy-pasting.', 2),
((select id from public.modules where slug='artifacts'), null,
 'Can an Artifact be working software?',
 '["No, Artifacts are always static text","Yes — Claude can write HTML/JavaScript that actually runs in the panel","Only if you can code yourself","Only spreadsheets"]'::jsonb,
 1, 'Claude can build real, runnable tools like calculators and dashboards as Artifacts.', 3),
((select id from public.modules where slug='artifacts'), null,
 'Which is the best candidate for an Artifact rather than a chat reply?',
 '["A one-word yes/no answer","A polished document or interactive tool you want to keep and refine","A quick clarifying question","A greeting"]'::jsonb,
 1, 'Artifacts shine for content you want to keep, edit, or share — documents, tables, tools, and charts.', 4),
((select id from public.modules where slug='artifacts'), 'recruitment',
 'What Artifact best structures feedback across a hiring loop?',
 '["A single Slack message","A shared interview scorecard with competencies, notes, scores, and a recommendation","A calendar invite","A resume PDF"]'::jsonb,
 1, 'A scorecard Artifact makes feedback consistent and comparable across every interviewer.', 5),
((select id from public.modules where slug='artifacts'), 'marketing',
 'How can an Artifact beat a static slide in a campaign review?',
 '["It prints faster","A clickable landing-page mockup lets stakeholders react and you tweak copy live","It uses fewer colors","It hides the CTA"]'::jsonb,
 1, 'A live mockup Artifact gives people something real to react to and edit during the meeting.', 6),
((select id from public.modules where slug='artifacts'), 'sales',
 'Which Artifact best proves value to a skeptical prospect?',
 '["A long email","An interactive ROI calculator they plug their own numbers into","A static price list","A company org chart"]'::jsonb,
 1, 'A live ROI calculator lets the prospect see their own savings and payback, making value concrete.', 7),
((select id from public.modules where slug='artifacts'), 'engineering',
 'How do Artifacts speed up validating a UI idea?',
 '["They auto-merge your branch","Claude builds a runnable component you click through and refine by describing changes","They rewrite your backend","They deploy to production"]'::jsonb,
 1, 'A runnable component Artifact lets you test a UI idea in minutes without scaffolding a project.', 8),
((select id from public.modules where slug='artifacts'), 'hr',
 'What reusable Artifact best supports onboarding?',
 '["A one-time welcome email","A phased checklist with owners and checkboxes you reuse for every hire","A single org chart","A payroll export"]'::jsonb,
 1, 'A phased onboarding checklist Artifact is built once and reused, giving every hire a consistent start.', 9),
((select id from public.modules where slug='artifacts'), 'finance',
 'How can an Artifact clarify budget scenarios for leadership?',
 '["By emailing three spreadsheets","An interactive dashboard where changing drivers updates revenue, cost, and margin live","By printing last year''s actuals","By hiding the assumptions"]'::jsonb,
 1, 'A live dashboard Artifact lets leadership watch assumptions flow to the bottom line in real time.', 10);

-- ---- tool-use -------------------------------------------------------------
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, order_index) values
((select id from public.modules where slug='tool-use'), null,
 'What does web search add to Claude?',
 '["A faster typing speed","The ability to fetch up-to-date facts and links in real time","A new color theme","Offline mode"]'::jsonb,
 1, 'Web search lets Claude look things up live and answer with current information and sources.', 1),
((select id from public.modules where slug='tool-use'), null,
 'What is a connector?',
 '["A cable for your monitor","A link between Claude and your own tools like Drive, Gmail, or GitHub","A pricing plan","A keyboard shortcut"]'::jsonb,
 1, 'Connectors link Claude to your systems so it can read or act on your files within granted permissions.', 2),
((select id from public.modules where slug='tool-use'), null,
 'What is the Model Context Protocol (MCP)?',
 '["A security password","The open standard for plugging internal systems into Claude","A type of quiz","A backup format"]'::jsonb,
 1, 'MCP is the open standard that makes tool use extensible, letting teams connect their own systems.', 3),
((select id from public.modules where slug='tool-use'), null,
 'When Claude uses tools on a high-stakes task, you should:',
 '["Trust every answer without checking","Verify by clicking the sources it cites","Disconnect all tools first","Grant access to everything you own"]'::jsonb,
 1, 'Tools reduce guesswork but you still verify anything high-stakes and grant only the access needed.', 4),
((select id from public.modules where slug='tool-use'), 'recruitment',
 'Before an intake call, how do tools help you prep?',
 '["They auto-schedule interviews","Search pulls current salary benchmarks and recent company news with links","They rank candidates for you","They write the offer letter alone"]'::jsonb,
 1, 'Web search gives you up-to-date pay ranges and fresh company news so your outreach is informed.', 5),
((select id from public.modules where slug='tool-use'), 'marketing',
 'Why rely on web search for competitor campaign research?',
 '["It is cheaper than reading","Positioning and trends change constantly, so search grounds strategy in what is happening now","It guarantees you win awards","It replaces your brand guide"]'::jsonb,
 1, 'Because competitor messaging shifts constantly, live search keeps your strategy current with citations.', 6),
((select id from public.modules where slug='tool-use'), 'sales',
 'How do search and a Drive connector build a pre-call brief?',
 '["They cold-call the prospect","Search pulls the account''s recent news — the connector pulls your last notes — Claude merges them","They delete old opportunities","They set the meeting price"]'::jsonb,
 1, 'Combining live news with your prior notes gives you a brief that is both current and continuous.', 7),
((select id from public.modules where slug='tool-use'), 'engineering',
 'Why connect Claude to your repo instead of pasting one file?',
 '["It deploys automatically","It can read the real files and tests and cross-check current API docs","It hides the code from review","It rewrites git history"]'::jsonb,
 1, 'Reading the actual code plus checking current docs grounds the analysis in reality, not a snippet.', 8),
((select id from public.modules where slug='tool-use'), 'hr',
 'How do tools help answer a tricky parental-leave question?',
 '["They approve the leave for you","A connector reads your policy while search checks current statutory rules, exposing any gap","They notify the whole company","They calculate payroll tax"]'::jsonb,
 1, 'Comparing your internal policy against current law with sources makes guidance on-policy and legally current.', 9),
((select id from public.modules where slug='tool-use'), 'finance',
 'Why use web search when refreshing forecast assumptions?',
 '["To make the file smaller","Rates, FX, and competitor figures must be current, and search retrieves them with citations","To avoid using Excel","To hide the assumptions tab"]'::jsonb,
 1, 'Live, cited figures for rates and reported numbers keep forecast assumptions on verifiable current data.', 10);

-- ---- workflows ------------------------------------------------------------
insert into public.quiz_questions (module_id, profession, question, options, correct_index, explanation, order_index) values
((select id from public.modules where slug='workflows'), null,
 'What best describes a Claude "workflow"?',
 '["A single well-written prompt","A repeatable sequence where each step''s output feeds the next","A billing cycle","A list of connectors"]'::jsonb,
 1, 'A workflow chains steps — research, draft, refine, format — into one steered sequence.', 1),
((select id from public.modules where slug='workflows'), null,
 'How do Projects, tools, and Artifacts support a workflow?',
 '["They replace the need for prompts","Projects load context, tools fetch live data, Artifacts hold deliverables","They only work separately","They slow it down"]'::jsonb,
 1, 'Each piece plays a role: context, live data, and keepable deliverables come together in the workflow.', 2),
((select id from public.modules where slug='workflows'), null,
 'How do you make a good workflow repeatable?',
 '["Memorize it perfectly","Save the sequence of prompts that worked as a reusable template","Never write it down","Change it every time"]'::jsonb,
 1, 'Saving the prompt chain turns next time into filling a template rather than starting from scratch.', 3),
((select id from public.modules where slug='workflows'), null,
 'What is the human''s role in a Claude workflow?',
 '["To step away entirely","To decide, verify, and own the result while Claude handles the busywork","To avoid reviewing anything","To only write the first prompt"]'::jsonb,
 1, 'Claude accelerates and organizes — you keep judgment in the loop and own the outcome.', 4),
((select id from public.modules where slug='workflows'), 'recruitment',
 'What does a hiring-kit workflow chain together?',
 '["Only a job posting","JD, then screening rubric, then outreach, then interview guide — each feeding the next","Payroll and benefits","A single interview question"]'::jsonb,
 1, 'The steps flow into one another and the whole chain is reusable for the next requisition.', 5),
((select id from public.modules where slug='workflows'), 'marketing',
 'A content-repurposing workflow turns one brief into:',
 '["A single tweet","A blog post, then social posts, an email, and ad variants — one coordinated package","Only an internal memo","A random assortment of files"]'::jsonb,
 1, 'One brief flows through a chain into an on-voice, multi-channel content package.', 6),
((select id from public.modules where slug='workflows'), 'sales',
 'Which sequence describes a prospecting workflow?',
 '["Email everyone the same template","Research account, personalize outreach, build follow-ups, write a CRM note","Wait for inbound leads","Only log calls"]'::jsonb,
 1, 'Research, personalization, follow-ups, and CRM notes flow as one repeatable motion per prospect.', 7),
((select id from public.modules where slug='workflows'), 'engineering',
 'A ticket-to-PR workflow moves through:',
 '["Straight to merging","Clarify, design with trade-offs, implement, test, then draft the PR description","Only writing tests","Deleting the ticket"]'::jsonb,
 1, 'Each stage produces reviewable work and the chain ends with a clean, documented PR.', 8),
((select id from public.modules where slug='workflows'), 'hr',
 'An onboarding workflow orchestrates:',
 '["Only a welcome email","The checklist, welcome comms and schedule, a 30-day check-in, and a manager briefing","Just the offer letter","Exit interviews"]'::jsonb,
 1, 'Running onboarding as one flow means every new hire gets a consistent, thorough start.', 9),
((select id from public.modules where slug='workflows'), 'finance',
 'A month-end close workflow chains:',
 '["Only printing the trial balance","Flag large movements, draft variance explanations, build the summary, list follow-ups","Paying invoices","Setting next year''s salaries"]'::jsonb,
 1, 'The close becomes a repeatable monthly chain from reconciliation flags to the management summary.', 10);

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
