"use client";

import { useState } from "react";
import Flashcards from "@/components/Flashcards";
import Quiz, { type QuizResult } from "@/components/Quiz";
import type { Flashcard, ModuleExample, QuizQuestion } from "@/lib/types";
import { getProfession } from "@/lib/professions";

type Tab = "learn" | "cards" | "quiz";

// Client shell that switches between the three learning surfaces of a module.
export default function ModuleWorkspace({
  learnContent,
  example,
  profession,
  flashcards,
  questions,
  onSubmitQuiz,
}: {
  learnContent: React.ReactNode;
  example: ModuleExample | null;
  profession: string | null;
  flashcards: Flashcard[];
  questions: QuizQuestion[];
  onSubmitQuiz: (score: number, total: number, answers: number[]) => Promise<QuizResult>;
}) {
  const [tab, setTab] = useState<Tab>("learn");
  const prof = getProfession(profession);

  const tabs: { key: Tab; label: string; icon: string }[] = [
    { key: "learn", label: "Learn", icon: "📖" },
    { key: "cards", label: `Flashcards (${flashcards.length})`, icon: "🃏" },
    { key: "quiz", label: `Quiz (${questions.length})`, icon: "🧩" },
  ];

  return (
    <div>
      <div className="mb-6 flex gap-2 rounded-2xl bg-white/70 p-1.5 backdrop-blur">
        {tabs.map((t) => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`flex-1 rounded-xl px-3 py-2.5 text-sm font-bold transition ${
              tab === t.key
                ? "bg-gradient-to-r from-indigo-600 to-fuchsia-600 text-white shadow-lg"
                : "text-slate-600 hover:bg-white"
            }`}
          >
            <span className="mr-1">{t.icon}</span>
            {t.label}
          </button>
        ))}
      </div>

      {tab === "learn" && (
        <div className="space-y-6">
          <div className="rounded-3xl border border-white/70 bg-white/90 p-7 shadow-lg">
            {learnContent}
          </div>

          {example && (
            <div className="overflow-hidden rounded-3xl border border-indigo-200 bg-white shadow-lg">
              <div className="bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-6 py-3 text-white">
                <span className="text-sm font-bold uppercase tracking-widest">
                  {prof ? `${prof.icon} For ${prof.label}` : "🎯 Worked example"}
                </span>
              </div>
              <div className="space-y-4 p-6">
                <div>
                  <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
                    The situation
                  </p>
                  <p className="mt-1 text-slate-700">{example.scenario}</p>
                </div>
                <div>
                  <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
                    A prompt you could use
                  </p>
                  <pre className="mt-1 overflow-x-auto whitespace-pre-wrap rounded-xl bg-slate-900 p-4 font-mono text-sm text-slate-100">
                    {example.sample_prompt}
                  </pre>
                </div>
                <div>
                  <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
                    What you get back
                  </p>
                  <p className="mt-1 text-slate-700">{example.outcome}</p>
                </div>
              </div>
            </div>
          )}

          <div className="flex justify-end">
            <button
              onClick={() => setTab("cards")}
              className="rounded-xl bg-slate-900 px-5 py-2.5 font-semibold text-white hover:bg-slate-800"
            >
              Review the flashcards →
            </button>
          </div>
        </div>
      )}

      {tab === "cards" && (
        <div>
          <Flashcards cards={flashcards} />
          <div className="mt-6 flex justify-end">
            <button
              onClick={() => setTab("quiz")}
              className="rounded-xl bg-slate-900 px-5 py-2.5 font-semibold text-white hover:bg-slate-800"
            >
              Take the quiz →
            </button>
          </div>
        </div>
      )}

      {tab === "quiz" && <Quiz questions={questions} onSubmit={onSubmitQuiz} />}
    </div>
  );
}
