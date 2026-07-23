# 🧠 Gyaan — Learn Claude, personalized to your profession

Gyaan is a full-stack, gamified Learning Management System that teaches people
how to use **Claude** (Anthropic's AI assistant). Instead of a one-size-fits-all
tutorial, every learner picks their profession at signup and gets a course whose
worked examples, flashcards, and quiz questions are drawn from **their** real
workflows — a recruiter and a finance analyst learning the same Claude feature
see genuinely different examples.

- **Full coverage of Claude:** chat basics, prompting, projects, artifacts,
  tool use, and end-to-end workflows.
- **Personalized:** examples tailored to Recruitment, Marketing, Sales,
  Engineering, HR, or Finance.
- **Interactive, not walls of text:** flip-to-reveal flashcards with a light
  spaced-review loop, and scored multiple-choice quizzes with instant feedback.
- **Hands-on practice (optional):** a "Practice" tab where you write a prompt for
  your scenario, send it to the **real Claude**, and get its response plus a
  rubric-graded critique — recognition turned into production.
- **Gamified:** earn brownie points and unlock badges as you complete modules.

Built with **Next.js 16** (App Router) + **TypeScript** + **Tailwind CSS**, with
**Supabase** (Auth + Postgres + Row Level Security) as the backend.

---

## Quick start

```bash
git clone <this-repo> gyaan
cd gyaan
npm install
cp .env.example .env.local     # then fill in your Supabase keys (below)
# ...run the SQL setup (below)...
npm run dev                    # http://localhost:3000
```

If you open the app before adding Supabase keys, every page renders a friendly
"finish setup" notice instead of crashing.

---

## 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → **New project** (the free tier is
   plenty). Wait for it to finish provisioning.
2. In **Project Settings → API**, copy:
   - **Project URL** → `NEXT_PUBLIC_SUPABASE_URL`
   - **anon public** key → `NEXT_PUBLIC_SUPABASE_ANON_KEY`
3. Paste both into `.env.local` (see `.env.example`).

## 2. Set up the database

Run the two SQL files **in order**. Two easy options:

**Option A — Supabase SQL Editor (no CLI needed):**

**Easiest: one paste.** Open your project → **SQL Editor**, paste the entire
contents of [`supabase/setup.sql`](supabase/setup.sql), and **Run**. That single
file applies every migration (schema + RLS, the Practice table, the
difficulty/kind/hint columns) and loads the full curriculum in one go. Safe to
re-run any time — including after pulling an update to this repo — since it
clears and reloads content without touching your users' accounts or progress.

Prefer to see each piece separately? Run the migration files in order — paste
each and **Run**: [`0001_schema.sql`](supabase/migrations/0001_schema.sql)
(tables, the profile-creation trigger, and RLS policies),
[`0002_practice.sql`](supabase/migrations/0002_practice.sql) (the Practice
table), [`0003_variety.sql`](supabase/migrations/0003_variety.sql) (difficulty
tiers, flashcard/quiz format variety, hints) — then paste
[`supabase/seed.sql`](supabase/seed.sql) and **Run** to load the curriculum.

**Option B — Supabase CLI:**

```bash
supabase link --project-ref <your-ref>
supabase db push                        # applies supabase/migrations/* in order
psql "$SUPABASE_DB_URL" -f supabase/seed.sql
# or, equivalently, just:
psql "$SUPABASE_DB_URL" -f supabase/setup.sql
```

Both SQL migrations and the seed have been verified to execute cleanly against a
real PostgreSQL 16 instance, with the RLS policies confirmed to isolate each
user's rows.

## 2b. The Practice tab & API keys (bring-your-own-key)

The **Practice** tab lets a learner write a prompt and get a real Claude response
plus coaching. It works three ways, in order of preference — **you don't have to
configure anything**:

1. **Bring-your-own-key (default):** each learner pastes their own Anthropic API
   key into the Practice tab. It's stored **only in their browser** (localStorage),
   passed to the grading Server Action per request, and **never saved or logged on
   the server**. Cost falls on the learner and is a cent or two per practice.
2. **Free offline check:** with no key at all, Practice still scores the prompt
   against a rubric (context, a clear ask, output constraints, an example) instantly
   and for free — lower fidelity, no live Claude response.
3. **Operator key (optional):** set `ANTHROPIC_API_KEY` in `.env.local` to provide
   live grading for everyone without them needing their own key.

Model defaults to `claude-opus-4-8`; override with `ANTHROPIC_MODEL` (e.g.
`claude-haiku-4-5` for the cheapest live grading).

## 3. Configure auth

- Email/password signup works out of the box.
- For the **smoothest local testing**, disable email confirmation:
  **Authentication → Providers → Email → turn off "Confirm email"**. New signups
  then land straight in onboarding.
- If you keep email confirmation on, add your site URL under
  **Authentication → URL Configuration → Redirect URLs**, e.g.
  `http://localhost:3000/auth/callback`. The confirmation link returns users to
  `/auth/callback` and on to onboarding.

## 4. Run it

```bash
npm run dev
```

Open http://localhost:3000, sign up, pick your profession, and start learning.

---

## Deploy it live (hosted)

Two things, both free-tier:

**1. Supabase (backend).** Create a project at [supabase.com](https://supabase.com),
then in **SQL Editor** paste [`supabase/setup.sql`](supabase/setup.sql) — a single
file that runs the schema, RLS, the practice table, and the full curriculum in one
go — and **Run**. Copy your **Project URL** and **anon key** from
**Project Settings → API**.

**2. Vercel (frontend).** Import this repo at [vercel.com/new](https://vercel.com/new)
(or use the button below) and set three env vars:

| Variable | Value |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | your Supabase Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | your Supabase anon key |
| `NEXT_PUBLIC_SITE_URL` | your Vercel URL, e.g. `https://your-app.vercel.app` |

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fgnaidu05%2Fgyaan&env=NEXT_PUBLIC_SUPABASE_URL,NEXT_PUBLIC_SUPABASE_ANON_KEY,NEXT_PUBLIC_SITE_URL&envDescription=Supabase%20Project%20URL%20%2B%20anon%20key%20(Project%20Settings%20%E2%86%92%20API)%20and%20your%20deployed%20site%20URL&project-name=gyaan&repository-name=gyaan)

Then in Supabase **Authentication → URL Configuration**, add your Vercel URL +
`/auth/callback` to **Redirect URLs**. Nothing else is needed — the app builds and
runs on Vercel's zero-config Next.js support. (No `ANTHROPIC_API_KEY` required:
learners bring their own key for the Practice tab, or use the free offline check.)

> The one-click button and a plain Vercel import both build the **default branch**,
> so the app code needs to be on `main` first (currently it lives on the
> `claude/lms-profession-personalization-k1ms8z` branch).

---

## How personalization works

Every learner walks the **same** curriculum so coverage of Claude is complete.
The personalization is a content layer, not a fork:

- Each module has a profession-agnostic lesson (`modules.core_content`).
- `module_examples` holds one authored example **per profession per module** — a
  real scenario, a sample prompt, and the expected outcome. The app selects the
  row matching the user's `profiles.profession`, falling back to a default so no
  one hits an empty screen.
- `flashcards` and `quiz_questions` are either generic (`profession IS NULL`,
  shown to everyone) or profession-specific (shown only to that profession). A
  learner sees the shared cards/questions **plus** the ones for their field.

The selection logic lives in [`src/lib/data.ts`](src/lib/data.ts).

## Flashcards & quizzes: a bigger pool, a fresh mix every time

Each module draws from a large content pool (27 flashcards and 27 quiz questions
per module, mixing generic + profession-specific) rather than a fixed set. Every
time a learner opens a module — including a fresh login — the app pulls a new
random, difficulty-scaffolded subset (8 flashcards, 6 quiz questions) and
reshuffles multiple-choice option order, so the same session is never repeated
and the correct answer isn't always in the same slot. The sampling logic is in
[`src/lib/session-pick.ts`](src/lib/session-pick.ts).

Content is also written like a **professional teacher** would structure a
lesson, not a flat list of trivia:

- **Three difficulty tiers** — `beginner` (recall), `intermediate` (application),
  `advanced` (judgment/trade-offs) — labeled in the UI as 🌱 Warm-up, 🚀 Level up,
  🏆 Challenge, and a session is scaffolded easy-to-hard.
- **Flashcard patterns** (`card_type`): `concept` (direct Q&A), `scenario` (a
  short workplace situation to reason through), `reverse` (shown the
  answer/definition first — recall the term).
- **Quiz formats** (`kind`): multiple choice, true/false, scenario-based, and
  fill-in-the-blank — mixed within a session rather than one repetitive format.
- **Hints.** Every question has an optional, teacher-style nudge the learner can
  reveal before answering, without giving away the answer.

Grading stays instant and free for all of this — every kind is still scored as
multiple choice under the hood (true/false is a 2-option MCQ, fill-in-the-blank's
options are candidate words), so no LLM call is needed to check an answer. Schema
in [`supabase/migrations/0003_variety.sql`](supabase/migrations/0003_variety.sql).

## Live practice (recognition → production)

Flashcards and quizzes test whether you *recognize* a good answer. The **Practice**
tab tests whether you can *produce* one. The learner writes a prompt for their
scenario; the grading Server Action either sends it to Claude — which returns a
structured JSON object with (a) the response Claude would give to that prompt and
(b) a rubric-graded critique — or, with no key, scores it via a free offline
heuristic ([`src/lib/practice-heuristic.ts`](src/lib/practice-heuristic.ts)). The
per-module rubric is in [`src/lib/practice.ts`](src/lib/practice.ts); the grading
and key resolution live in
[`src/app/modules/[slug]/practice-actions.ts`](src/app/modules/%5Bslug%5D/practice-actions.ts).
The learner's key (BYOK) is held only in their browser and passed per request —
`src/lib/anthropic.ts` never reads it from anywhere but the incoming argument (or
the optional operator env key). Attempts are stored in `practice_attempts`
(RLS-protected); a first attempt plus a strong prompt (≥80) award points.

## Gamification

- **Brownie points** are an append-only ledger (`point_events`); a user's total
  is the sum of their deltas. Completing a module (quiz ≥ 60%) awards its points
  once; a perfect quiz adds a bonus.
- **Badges** (`badges` / `user_badges`) unlock on milestones: first module,
  two-module streak, halfway, all modules, any perfect score, and acing the
  Prompting quiz. Awarding is idempotent.
- All of this runs server-side in `src/app/modules/[slug]/actions.ts`.

## Security (Row Level Security)

Content tables are readable by any authenticated user. Every **per-user** table
(`profiles`, `module_progress`, `quiz_attempts`, `point_events`, `user_badges`)
is protected by RLS so a row is only visible/editable when
`row.user_id = auth.uid()`. Users can never see anyone else's progress.

## Project structure

```
supabase/
  migrations/0001_schema.sql   # tables + RLS + trigger
  seed.sql                     # curriculum content
src/
  app/
    page.tsx                   # landing
    login/                     # signup / login (Supabase Auth)
    onboarding/                # profession picker
    dashboard/                 # learning path, points, badges
    modules/[slug]/            # a module: Learn / Flashcards / Quiz
    auth/                      # callback + signout route handlers
  components/                  # Flashcards, Quiz, Markdown, AppHeader, ...
  lib/
    supabase/                  # browser + server clients, session proxy
    data.ts                    # personalization + gamification reads
    professions.ts             # the professions we tailor to
  proxy.ts                     # refreshes session, gates private routes
```

## Tech & licenses

- [Next.js](https://nextjs.org) (MIT), [React](https://react.dev) (MIT),
  [Tailwind CSS](https://tailwindcss.com) (MIT)
- [`@supabase/supabase-js`](https://github.com/supabase/supabase-js) &
  [`@supabase/ssr`](https://github.com/supabase/auth-helpers) (MIT)
- [`react-markdown`](https://github.com/remarkjs/react-markdown) +
  [`remark-gfm`](https://github.com/remarkjs/remark-gfm) (MIT) for lesson content
- [`@anthropic-ai/sdk`](https://github.com/anthropics/anthropic-sdk-typescript)
  (MIT) — powers the optional live Practice tab

All dependencies are permissively licensed. This project is licensed under
GPL-3.0 (see [LICENSE](LICENSE)).

## Scripts

```bash
npm run dev      # dev server
npm run build    # production build
npm run start    # serve the production build
npm run lint     # eslint
```
