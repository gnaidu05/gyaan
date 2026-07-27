"use client";

import { useState, useTransition } from "react";
import type { QuizQuestion } from "@/lib/types";

export type QuizResult = {
  pointsAwarded: number;
  totalPoints: number;
  newBadges: { name: string; icon: string }[];
  moduleCompleted: boolean;
};

const DIFFICULTY_BADGE: Record<string, { label: string; icon: string; cls: string }> = {
  beginner: { label: "Warm-up", icon: "🌱", cls: "bg-emerald-100 text-emerald-700" },
  intermediate: { label: "Level up", icon: "🚀", cls: "bg-indigo-100 text-indigo-700" },
  advanced: { label: "Challenge", icon: "🏆", cls: "bg-rose-100 text-rose-700" },
};

const KIND_LABEL: Record<string, string> = {
  mcq: "Multiple choice",
  true_false: "True or false",
  scenario: "Scenario",
  fill_blank: "Fill in the blank",
};

// Teacher-voice reactions so feedback doesn't feel like a form validator.
const CORRECT_LINES = [
  "Nice catch!",
  "Exactly right.",
  "That's the one — well spotted.",
  "Yes! You've got this.",
];
const INCORRECT_LINES = [
  "Not quite — here's the idea:",
  "Close, but let's look again:",
  "A common mix-up. Here's why:",
  "Good try — the key detail is this:",
];
function pickLine(lines: string[], seed: number) {
  return lines[seed % lines.length];
}

// Interactive scored quiz: one question at a time, difficulty-tagged and
// kind-varied (multiple choice / true-false / scenario / fill-in-the-blank),
// with an optional teacher hint, immediate feedback, a running score, and a
// results screen. On finish it calls the server action to persist the
// attempt and award points/badges.
export default function Quiz({
  questions,
  onSubmit,
}: {
  questions: QuizQuestion[];
  onSubmit: (score: number, total: number, answers: number[]) => Promise<QuizResult>;
}) {
  const [idx, setIdx] = useState(0);
  const [answers, setAnswers] = useState<number[]>([]);
  const [picked, setPicked] = useState<number | null>(null);
  const [hintShown, setHintShown] = useState(false);
  const [finished, setFinished] = useState(false);
  const [result, setResult] = useState<QuizResult | null>(null);
  const [pending, startTransition] = useTransition();

  if (questions.length === 0) {
    return (
      <p className="rounded-2xl bg-white/70 p-6 text-slate-500">
        No quiz questions for this module yet.
      </p>
    );
  }

  const q = questions[idx];
  const score = answers.reduce(
    (s, a, i) => s + (a === questions[i].correct_index ? 1 : 0),
    0,
  );
  const badge = DIFFICULTY_BADGE[q.difficulty] ?? DIFFICULTY_BADGE.beginner;
  const isTwoUp = q.kind === "true_false" && q.options.length === 2;

  function choose(i: number) {
    if (picked !== null) return; // locked once answered
    setPicked(i);
    setAnswers((prev) => {
      const next = [...prev];
      next[idx] = i;
      return next;
    });
  }

  function next() {
    if (idx + 1 < questions.length) {
      setIdx(idx + 1);
      setPicked(null);
      setHintShown(false);
    } else {
      const finalScore = answers.reduce(
        (s, a, i) => s + (a === questions[i].correct_index ? 1 : 0),
        0,
      );
      startTransition(async () => {
        const r = await onSubmit(finalScore, questions.length, answers);
        setResult(r);
        setFinished(true);
      });
    }
  }

  function retake() {
    setIdx(0);
    setAnswers([]);
    setPicked(null);
    setHintShown(false);
    setFinished(false);
    setResult(null);
  }

  if (finished && result) {
    const pct = Math.round((score / questions.length) * 100);
    const passed = pct >= 60;
    return (
      <div className="animate-pop rounded-3xl border border-white/70 bg-white p-8 text-center shadow-xl">
        <div className="text-5xl">{pct === 100 ? "🏆" : passed ? "🎉" : "💪"}</div>
        <h3 className="mt-3 text-2xl font-black">
          {score}/{questions.length} correct
        </h3>
        <p className="mt-1 text-slate-500">{pct}% score</p>

        {result.pointsAwarded > 0 && (
          <div className="mx-auto mt-5 inline-flex items-center gap-2 rounded-full bg-amber-100 px-5 py-2 text-lg font-bold text-amber-700">
            +{result.pointsAwarded} brownie points 🪙
          </div>
        )}

        {result.newBadges.length > 0 && (
          <div className="mt-5">
            <p className="text-sm font-semibold text-slate-500">Badge unlocked!</p>
            <div className="mt-2 flex flex-wrap justify-center gap-2">
              {result.newBadges.map((b) => (
                <span
                  key={b.name}
                  className="animate-pop inline-flex items-center gap-2 rounded-full border border-indigo-200 bg-indigo-50 px-4 py-1.5 font-semibold text-indigo-700"
                >
                  <span className="text-xl">{b.icon}</span> {b.name}
                </span>
              ))}
            </div>
          </div>
        )}

        <p className="mt-5 text-slate-600">
          {result.moduleCompleted
            ? "Module complete — the next one is unlocked on your dashboard."
            : "Score 60% or higher to complete this module and unlock the next one."}
        </p>
        <p className="mt-2 text-xs text-slate-400">
          New question mix next time you take this quiz — retake it any time for fresh
          practice.
        </p>

        <div className="mt-6 flex flex-wrap justify-center gap-3">
          <button
            onClick={retake}
            className="rounded-xl border border-slate-300 bg-white px-5 py-2.5 font-semibold text-slate-600 hover:bg-slate-50"
          >
            Retake quiz
          </button>
          <a
            href="/dashboard"
            className="rounded-xl bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-5 py-2.5 font-semibold text-white shadow-lg hover:brightness-110"
          >
            Back to dashboard →
          </a>
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-3xl border border-white/70 bg-white p-7 shadow-xl">
      <div className="mb-4 flex flex-wrap items-center justify-between gap-2 text-sm font-medium text-slate-500">
        <span>
          Question {idx + 1} of {questions.length}
          {q.profession ? " · 🎯 applied to your role" : ""}
        </span>
        <span>Score: {score}</span>
      </div>
      <div className="mb-4 h-2 w-full overflow-hidden rounded-full bg-slate-200">
        <div
          className="h-full rounded-full bg-gradient-to-r from-indigo-500 to-fuchsia-500 transition-all"
          style={{ width: `${(idx / questions.length) * 100}%` }}
        />
      </div>

      <div className="mb-2 flex flex-wrap items-center gap-2">
        <span className={`inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-bold ${badge.cls}`}>
          {badge.icon} {badge.label}
        </span>
        <span className="inline-flex items-center gap-1 rounded-full bg-slate-100 px-3 py-1 text-xs font-bold text-slate-500">
          {KIND_LABEL[q.kind] ?? "Question"}
        </span>
      </div>

      <h3 className="text-xl font-semibold text-slate-800">{q.question}</h3>

      {q.hint && picked === null && (
        <div className="mt-3">
          {hintShown ? (
            <p className="rounded-xl bg-amber-50 px-4 py-2.5 text-sm text-amber-800">
              💡 {q.hint}
            </p>
          ) : (
            <button
              onClick={() => setHintShown(true)}
              className="text-sm font-semibold text-amber-600 hover:text-amber-800 hover:underline"
            >
              💡 Ask your teacher for a hint
            </button>
          )}
        </div>
      )}

      <div className={`mt-5 ${isTwoUp ? "grid grid-cols-2 gap-3" : "space-y-3"}`}>
        {q.options.map((opt, i) => {
          const isCorrect = i === q.correct_index;
          const isPicked = picked === i;
          let cls =
            "border-slate-200 bg-white hover:border-indigo-300 hover:bg-indigo-50/40";
          if (picked !== null) {
            if (isCorrect) cls = "border-emerald-400 bg-emerald-50";
            else if (isPicked) cls = "border-rose-400 bg-rose-50";
            else cls = "border-slate-200 bg-white opacity-70";
          }
          return (
            <button
              key={i}
              onClick={() => choose(i)}
              disabled={picked !== null}
              className={`flex w-full items-center justify-between rounded-xl border px-4 py-3 text-left font-medium transition ${cls} ${
                isTwoUp ? "justify-center text-center text-lg font-bold" : ""
              }`}
            >
              <span>{opt}</span>
              {picked !== null && isCorrect && <span>✅</span>}
              {picked !== null && isPicked && !isCorrect && <span>❌</span>}
            </button>
          );
        })}
      </div>

      {picked !== null && (
        <p className="mt-4 rounded-xl bg-slate-50 px-4 py-3 text-sm text-slate-600">
          <span className="font-semibold text-slate-700">
            {picked === q.correct_index
              ? pickLine(CORRECT_LINES, idx)
              : pickLine(INCORRECT_LINES, idx)}{" "}
          </span>
          {q.explanation}
        </p>
      )}

      <button
        onClick={next}
        disabled={picked === null || pending}
        className="mt-6 w-full rounded-xl bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-4 py-3 font-bold text-white shadow-lg transition hover:brightness-110 disabled:opacity-50"
      >
        {pending
          ? "Saving…"
          : idx + 1 < questions.length
            ? "Next question →"
            : "Finish quiz"}
      </button>
    </div>
  );
}
