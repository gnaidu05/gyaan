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
