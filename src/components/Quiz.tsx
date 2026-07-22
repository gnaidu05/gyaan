"use client";

import { useState, useTransition } from "react";
import type { QuizQuestion } from "@/lib/types";

export type QuizResult = {
  pointsAwarded: number;
  totalPoints: number;
  newBadges: { name: string; icon: string }[];
  moduleCompleted: boolean;
};

// Interactive scored quiz: one question at a time, immediate feedback with an
// explanation, running score, and a results screen. On finish it calls the
// server action to persist the attempt and award points/badges.
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
      <div className="mb-4 flex items-center justify-between text-sm font-medium text-slate-500">
        <span>
          Question {idx + 1} of {questions.length}
          {q.profession ? " · 🎯 applied to your role" : ""}
        </span>
        <span>Score: {score}</span>
      </div>
      <div className="mb-5 h-2 w-full overflow-hidden rounded-full bg-slate-200">
        <div
          className="h-full rounded-full bg-gradient-to-r from-indigo-500 to-fuchsia-500 transition-all"
          style={{ width: `${(idx / questions.length) * 100}%` }}
        />
      </div>

      <h3 className="text-xl font-semibold text-slate-800">{q.question}</h3>

      <div className="mt-5 space-y-3">
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
              className={`flex w-full items-center justify-between rounded-xl border px-4 py-3 text-left font-medium transition ${cls}`}
            >
              <span>{opt}</span>
              {picked !== null && isCorrect && <span>✅</span>}
              {picked !== null && isPicked && !isCorrect && <span>❌</span>}
            </button>
          );
        })}
      </div>

      {picked !== null && q.explanation && (
        <p className="mt-4 rounded-xl bg-slate-50 px-4 py-3 text-sm text-slate-600">
          <span className="font-semibold text-slate-700">Why: </span>
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
