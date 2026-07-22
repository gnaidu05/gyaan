// The professions we personalize learning paths for. `key` matches the
// `profession` column used across module_examples, flashcards and quiz_questions.
export type Profession = {
  key: string;
  label: string;
  icon: string;
  blurb: string;
  accent: string; // tailwind gradient stops
};

export const PROFESSIONS: Profession[] = [
  {
    key: "recruitment",
    label: "Recruitment & Talent",
    icon: "🧲",
    blurb: "Sourcing, screening, outreach, interviews.",
    accent: "from-rose-500 to-orange-400",
  },
  {
    key: "marketing",
    label: "Marketing",
    icon: "📣",
    blurb: "Campaigns, content, positioning, SEO.",
    accent: "from-fuchsia-500 to-pink-400",
  },
  {
    key: "sales",
    label: "Sales",
    icon: "💼",
    blurb: "Prospecting, discovery, proposals, follow-ups.",
    accent: "from-emerald-500 to-teal-400",
  },
  {
    key: "engineering",
    label: "Engineering",
    icon: "🛠️",
    blurb: "Coding, debugging, reviews, docs.",
    accent: "from-sky-500 to-indigo-400",
  },
  {
    key: "hr",
    label: "People & HR",
    icon: "🤝",
    blurb: "Policies, onboarding, comms, culture.",
    accent: "from-violet-500 to-purple-400",
  },
  {
    key: "finance",
    label: "Finance",
    icon: "📊",
    blurb: "Analysis, reporting, modeling, forecasting.",
    accent: "from-amber-500 to-yellow-400",
  },
];

export const PROFESSION_KEYS = PROFESSIONS.map((p) => p.key);

export function getProfession(key: string | null | undefined): Profession | undefined {
  if (!key) return undefined;
  return PROFESSIONS.find((p) => p.key === key);
}

export const DEFAULT_PROFESSION = "marketing";
