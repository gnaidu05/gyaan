"use client";

import { useState, useTransition } from "react";
import type { PracticeResult } from "@/app/modules/[slug]/practice-actions";

// Live prompt practice: the learner writes a prompt for their scenario, sends it
// to Claude, and gets back both Claude's real answer and a rubric-graded critique.
// This is the "learn Claude by using Claude" surface.
export default function PromptPractice({
  scenario,
  samplePrompt,
  configured,
  onSubmit,
}: {
  scenario: string;
  samplePrompt: string;
  configured: boolean;
  onSubmit: (scenario: string, prompt: string) => Promise<PracticeResult>;
}) {
  const [text, setText] = useState("");
  const [result, setResult] = useState<PracticeResult | null>(null);
  const [pending, startTransition] = useTransition();

  function run() {
    if (text.trim().length < 10) return;
    startTransition(async () => {
      const r = await onSubmit(scenario, text);
      setResult(r);
    });
  }

  if (!configured) {
    return (
      <div className="rounded-3xl border border-amber-200 bg-amber-50 p-6">
        <div className="text-3xl">🔑</div>
        <h3 className="mt-2 text-lg font-bold text-amber-800">
          Live practice needs an Anthropic API key
        </h3>
        <p className="mt-1 text-amber-700">
          The Learn, Flashcards, and Quiz tabs work without it. To enable hands-on
          practice — where you write a prompt and get a real Claude response plus
          coaching — add <code className="rounded bg-white/70 px-1.5 py-0.5">ANTHROPIC_API_KEY</code>{" "}
          to <code className="rounded bg-white/70 px-1.5 py-0.5">.env.local</code> and restart. See the README.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-5">
      <div className="rounded-3xl border border-white/70 bg-white p-6 shadow-lg">
        <p className="text-xs font-bold uppercase tracking-wider text-slate-400">
          Your challenge
        </p>
        <p className="mt-1 text-slate-700">{scenario}</p>

        <label className="mt-4 block text-sm font-semibold text-slate-600">
          Write a prompt you&apos;d send to Claude for this:
        </label>
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          rows={7}
          placeholder="Type your prompt here… be specific, give context, say what good looks like."
          className="mt-2 w-full resize-y rounded-xl border border-slate-200 bg-white p-4 font-mono text-sm outline-none focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200"
        />

        <div className="mt-3 flex flex-wrap items-center gap-3">
          <button
            onClick={run}
            disabled={pending || text.trim().length < 10}
            className="rounded-xl bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-5 py-2.5 font-bold text-white shadow-lg transition hover:brightness-110 disabled:opacity-50"
          >
            {pending ? "Sending to Claude…" : "Send & get feedback →"}
          </button>
          <button
            onClick={() => setText(samplePrompt)}
            disabled={pending}
            className="text-sm font-semibold text-slate-500 hover:text-slate-800"
          >
            Prefill the lesson&apos;s example prompt
          </button>
        </div>
      </div>

      {result && !result.ok && (
        <p className="rounded-xl bg-rose-50 px-4 py-3 text-sm text-rose-700">
          {result.error}
        </p>
      )}

      {result && result.ok && (
        <div className="animate-pop space-y-5">
          {/* Score + points */}
          <div className="flex flex-wrap items-center gap-3 rounded-3xl border border-white/70 bg-white p-5 shadow-lg">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-br from-indigo-500 to-fuchsia-500 text-2xl font-black text-white">
              {result.score}
            </div>
            <div>
              <p className="font-bold text-slate-800">Prompt score: {result.score}/100</p>
              <p className="text-sm text-slate-500">
                {result.score! >= 80
                  ? "Strong prompt — this is how a pro asks."
                  : result.score! >= 60
                    ? "Solid. Tighten the improvements below to level up."
                    : "Good start — the tips below will sharpen it fast."}
              </p>
            </div>
            {result.pointsAwarded ? (
              <span className="ml-auto inline-flex items-center gap-1.5 rounded-full bg-amber-100 px-4 py-1.5 font-bold text-amber-700">
                +{result.pointsAwarded} 🪙
              </span>
            ) : null}
          </div>

          {/* Claude's actual response to their prompt */}
          <div className="overflow-hidden rounded-3xl border border-indigo-200 bg-white shadow-lg">
            <div className="bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-6 py-3 text-white">
              <span className="text-sm font-bold uppercase tracking-widest">
                🧠 What Claude returned to your prompt
              </span>
            </div>
            <div className="whitespace-pre-wrap p-6 text-slate-700">
              {result.assistantResponse}
            </div>
          </div>

          {/* Coaching */}
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="rounded-3xl border border-emerald-200 bg-emerald-50 p-5">
              <p className="font-bold text-emerald-800">✅ What worked</p>
              <ul className="mt-2 space-y-1.5 text-sm text-emerald-900">
                {result.strengths?.map((s, i) => (
                  <li key={i} className="flex gap-2">
                    <span>•</span>
                    <span>{s}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div className="rounded-3xl border border-amber-200 bg-amber-50 p-5">
              <p className="font-bold text-amber-800">🔧 Make it stronger</p>
              <ul className="mt-2 space-y-1.5 text-sm text-amber-900">
                {result.improvements?.map((s, i) => (
                  <li key={i} className="flex gap-2">
                    <span>•</span>
                    <span>{s}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <button
            onClick={() => setResult(null)}
            className="rounded-xl border border-slate-300 bg-white px-5 py-2.5 font-semibold text-slate-600 hover:bg-slate-50"
          >
            Try another prompt
          </button>
        </div>
      )}
    </div>
  );
}
