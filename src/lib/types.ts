// Shared DB row shapes (kept in sync with supabase/migrations/0001_schema.sql).

export type Profile = {
  id: string;
  email: string | null;
  full_name: string | null;
  profession: string | null;
  onboarded: boolean;
  created_at: string;
};

export type Module = {
  id: string;
  slug: string;
  title: string;
  subtitle: string | null;
  feature_area: string;
  order_index: number;
  core_content: string;
  icon: string | null;
  accent: string | null;
  points_reward: number;
};

export type ModuleExample = {
  id: string;
  module_id: string;
  profession: string;
  scenario: string;
  sample_prompt: string;
  outcome: string;
};

export type Flashcard = {
  id: string;
  deck_id: string;
  profession: string | null;
  front: string;
  back: string;
  order_index: number;
};

export type QuizQuestion = {
  id: string;
  module_id: string;
  profession: string | null;
  question: string;
  options: string[];
  correct_index: number;
  explanation: string | null;
  order_index: number;
};

export type ModuleProgress = {
  id: string;
  user_id: string;
  module_id: string;
  status: "in_progress" | "completed";
  best_score: number | null;
  quiz_total: number | null;
  started_at: string;
  completed_at: string | null;
};

export type Badge = {
  id: string;
  slug: string;
  name: string;
  description: string;
  icon: string;
};
