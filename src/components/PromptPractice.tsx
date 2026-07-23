"use client";

import { useEffect, useState, useTransition } from "react";
import type { PracticeResult } from "@/app/modules/[slug]/practice-actions";

const KEY_STORAGE = "gyaan_anthropic_key";

// Live prompt practice with bring-your-own-key. The learner's Anthropic API key
// is kept ONLY in their browser (localStorage) and passed to the grading action
// per request — it is never stored on the server. With no key, a free offline
// heuristic still scores the prompt.
export default function PromptPractice({
  scenario,
  samplePrompt,
  operatorConfigured,
  onSubmit,
}: {
  scenario: string;
  samplePrompt: string;
  operatorConfigured: boolean; // deployment provides a shared key
  onSubmit: (
    scenario: string,
    prompt: string,
    apiKey: string,
  ) => Promise<PracticeResult>;
}) {
  const [text, setText] = useState("");
  const [result, setResult] = useState<PracticeResult | null>(null);
  const [pending, startTransition] = useTransition();

  // { saved: persisted key, input: edit buffer }. Starts empty so server and
  // first client render match; the real value is loaded from localStorage on mount.
  const [key, setKey] = useState({ saved: "", input: "" });
  const [showKeyBox, setShowKeyBox] = useState(false);

  useEffect(() => {
    const saved = localStorage.getItem(KEY_STORAGE) || "";
    // localStorage is client-only, so this must run in an effect, not in init.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setKey({ saved, input: saved });
  }, []);

  const apiKey = key.saved;
  const keyInput = key.input;
  const setKeyInput = (input: string) => setKey((k) => ({ ...k, input }));

  function saveKey() {
    const k = keyInput.trim();
    localStorage.setItem(KEY_STORAGE, k);
    setKey({ saved: k, input: k });
    setShowKeyBox(false);
  }
  function clearKey() {
    localStorage.removeItem(KEY_STORAGE);
    setKey({ saved: "", input: "" });
  }

  function run() {
    if (text.trim().length < 10) return;
    startTransition(async () => {
      const r = await onSubmit(scenario, text, apiKey);
      setResult(r);
    });
  }

  const hasKey = apiKey.length > 0;
  const liveAvailable = hasKey || operatorConfigured;

  return (
    <div className="space-y-5">
      {/* Key / mode bar */}
      <div className="rounded-2xl border border-white/70 bg-white/80 p-4 backdrop-blur">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="text-sm">
            {hasKey ? (
              <span className="font-semibold text-emerald-700">
                🔑 Using your API key — live Claude grading
              </span>
            ) : operatorConfigured ? (
              <span className="font-semibold text-emerald-700">
                🔑 Live Claude grading enabled
              </span>
            ) : (
              <span className="font-semibold text-slate-600">
                ⚡ Free instant feedback — add your Anthropic key for a real Claude response
              </span>
            )}
          </div>
          <button
            onClick={() => setShowKeyBox((s) => !s)}
            className="text-sm font-semibold text-indigo-600 hover:underline"
          >
            {hasKey ? "Change / remove key" : "Add your API key"}
          </button>
        </div>

        {showKeyBox && (
          <div className="mt-3 border-t border-slate-100 pt-3">
            <label className="block text-sm font-medium text-slate-600">
              Anthropic API key
            </label>
            <div className="mt-1 flex flex-wrap gap-2">
              <input
                value={keyInput}
                onChange={(e) => setKeyInput(e.target.value)}
                type="password"
                placeholder="sk-ant-…"
                className="min-w-[240px] flex-1 rounded-xl border border-slate-200 bg-white px-3 py-2 font-mono text-sm outline-none focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200"
              />
              <button
                onClick={saveKey}
                className="rounded-xl bg-indigo-600 px-4 py-2 text-sm font-semibold text-white hover:brightness-110"
              >
                Save
              </button>
              {hasKey && (
                <button
                  onClick={clearKey}
                  className="rounded-xl border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-600 hover:bg-slate-50"
                >
                  Remove
                </button>
              )}
            </div>
            <p className="mt-2 text-xs text-slate-500">
              Your key is stored <strong>only in this browser</strong> and used just to
              grade your prompt. It is never saved on our servers. Get one at{" "}
              <a
                href="https://console.anthropic.com/settings/keys"
                target="_blank"
                rel="noreferrer"
                className="text-indigo-600 underline"
              >
                console.anthropic.com
              </a>
              . A practice costs a cent or two.
            </p>
          </div>
        )}
      </div>

      {/* Challenge + editor */}
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
            {pending
              ? liveAvailable
                ? "Sending to Claude…"
                : "Checking…"
              : liveAvailable
                ? "Send & get feedback →"
                : "Get instant feedback →"}
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

          {/* Claude's actual response (live) OR a note (heuristic) */}
          {result.mode === "live" && result.assistantResponse ? (
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
          ) : (
            <div className="rounded-3xl border border-slate-200 bg-slate-50 p-5 text-sm text-slate-600">
              <span className="font-semibold text-slate-700">⚡ Free mode.</span> This is
              an instant rubric check, not a live Claude response. Add your Anthropic API
              key above to see exactly what Claude returns to your prompt.
            </div>
          )}

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
