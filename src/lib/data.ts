import { createClient } from "@/lib/supabase/server";
import { DEFAULT_PROFESSION } from "@/lib/professions";
import { pickSession, shuffleOptions } from "@/lib/session-pick";
import type {
  Badge,
  Flashcard,
  Module,
  ModuleExample,
  ModuleProgress,
  Profile,
  QuizQuestion,
} from "@/lib/types";

// How many items a single Flashcards / Quiz session draws from the pool.
const FLASHCARD_SESSION_SIZE = 8;
const QUIZ_SESSION_SIZE = 6;

// ---------------------------------------------------------------------------
// Personalization engine
// ---------------------------------------------------------------------------
// The core idea: every learner walks the same curriculum (full coverage of
// Claude), but the *worked example*, some flashcards, and one quiz question per
// module are swapped for the version authored for their profession. Generic
// content (profession = NULL) is always shown; profession content is layered on
// top. If a profession somehow has no authored example we fall back to a
// default so the learner never hits an empty screen.

export async function getProfile(): Promise<Profile | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single();
  return (data as Profile) ?? null;
}

export type ModuleWithProgress = Module & {
  progress: ModuleProgress | null;
  locked: boolean;
};

// Dashboard view: all modules in order, each annotated with the user's progress
// and whether it is unlocked (a module unlocks once the previous is completed).
export async function getLearningPath(): Promise<ModuleWithProgress[]> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];

  const [{ data: modules }, { data: progress }] = await Promise.all([
    supabase.from("modules").select("*").order("order_index"),
    supabase.from("module_progress").select("*").eq("user_id", user.id),
  ]);

  const mods = (modules as Module[]) ?? [];
  const prog = (progress as ModuleProgress[]) ?? [];
  const byModule = new Map(prog.map((p) => [p.module_id, p]));

  let prevCompleted = true; // first module always unlocked
  return mods.map((m) => {
    const p = byModule.get(m.id) ?? null;
    const locked = !prevCompleted;
    prevCompleted = p?.status === "completed";
    return { ...m, progress: p, locked };
  });
}

export type ModuleDetail = {
  module: Module;
  example: ModuleExample | null;
  flashcards: Flashcard[];
  questions: QuizQuestion[];
  progress: ModuleProgress | null;
};

export async function getModuleDetail(
  slug: string,
  profession: string | null,
): Promise<ModuleDetail | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const prof = profession || DEFAULT_PROFESSION;

  const { data: module } = await supabase
    .from("modules")
    .select("*")
    .eq("slug", slug)
    .single();
  if (!module) return null;
  const mod = module as Module;

  const [examplesRes, decksRes, questionsRes, progressRes] = await Promise.all([
    supabase.from("module_examples").select("*").eq("module_id", mod.id),
    supabase.from("flashcard_decks").select("id").eq("module_id", mod.id),
    supabase
      .from("quiz_questions")
      .select("*")
      .eq("module_id", mod.id)
      .order("order_index"),
    supabase
      .from("module_progress")
      .select("*")
      .eq("user_id", user.id)
      .eq("module_id", mod.id)
      .maybeSingle(),
  ]);

  // Personalized example with default fallback.
  const examples = (examplesRes.data as ModuleExample[]) ?? [];
  const example =
    examples.find((e) => e.profession === prof) ??
    examples.find((e) => e.profession === DEFAULT_PROFESSION) ??
    examples[0] ??
    null;

  // Flashcards: generic (NULL) + this profession's cards, pooled, then a fresh
  // shuffled session-sized subset drawn on every render.
  const deckIds = ((decksRes.data as { id: string }[]) ?? []).map((d) => d.id);
  let flashcardPool: Flashcard[] = [];
  if (deckIds.length) {
    const { data: cards } = await supabase
      .from("flashcards")
      .select("*")
      .in("deck_id", deckIds)
      .or(`profession.is.null,profession.eq.${prof}`);
    flashcardPool = (cards as Flashcard[]) ?? [];
  }
  const flashcards = pickSession(flashcardPool, FLASHCARD_SESSION_SIZE);

  // Quiz: generic + this profession's questions, pooled, then a fresh session
  // draw with option order reshuffled so the answer position also varies.
  const allQuestions = (questionsRes.data as QuizQuestion[]) ?? [];
  const questionPool = allQuestions.filter(
    (q) => q.profession === null || q.profession === prof,
  );
  const questions = pickSession(questionPool, QUIZ_SESSION_SIZE).map(shuffleOptions);

  return {
    module: mod,
    example,
    flashcards,
    questions,
    progress: (progressRes.data as ModuleProgress) ?? null,
  };
}

// ---------------------------------------------------------------------------
// Gamification reads
// ---------------------------------------------------------------------------
export async function getPointsTotal(): Promise<number> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return 0;

  const { data } = await supabase
    .from("point_events")
    .select("delta")
    .eq("user_id", user.id);
  return ((data as { delta: number }[]) ?? []).reduce((s, r) => s + r.delta, 0);
}

export async function getEarnedBadges(): Promise<Badge[]> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];

  const { data } = await supabase
    .from("user_badges")
    .select("badge:badges(*)")
    .eq("user_id", user.id);

  return ((data as unknown as { badge: Badge }[]) ?? []).map((r) => r.badge);
}

export async function getAllBadges(): Promise<Badge[]> {
  const supabase = await createClient();
  const { data } = await supabase.from("badges").select("*");
  return (data as Badge[]) ?? [];
}
