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

1. Open your project → **SQL Editor**.
2. Paste the contents of [`supabase/migrations/0001_schema.sql`](supabase/migrations/0001_schema.sql)
   and **Run**. This creates all tables, the profile-creation trigger, and the
   Row Level Security policies.
3. Paste the contents of [`supabase/seed.sql`](supabase/seed.sql) and **Run**.
   This loads the curriculum: 6 modules, per-profession examples, flashcards,
   quizzes, and badges.

**Option B — Supabase CLI:**

```bash
supabase link --project-ref <your-ref>
supabase db push                        # applies supabase/migrations/*
psql "$SUPABASE_DB_URL" -f supabase/seed.sql
```

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

All dependencies are permissively licensed. This project is licensed under
GPL-3.0 (see [LICENSE](LICENSE)).

## Scripts

```bash
npm run dev      # dev server
npm run build    # production build
npm run start    # serve the production build
npm run lint     # eslint
```
