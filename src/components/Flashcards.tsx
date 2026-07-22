"use client";

import { useMemo, useState } from "react";
import type { Flashcard } from "@/lib/types";

// Interactive flashcard reviewer: flip to reveal, self-rate ("Got it" / "Review
// again"), and cards you miss are re-queued at the end — a light spaced-review
// loop. Progress bar tracks unique cards mastered.
export default function Flashcards({ cards }: { cards: Flashcard[] }) {
  const initial = useMemo(() => cards.map((c) => c.id), [cards]);
  const [queue, setQueue] = useState<string[]>(initial);
  const [pos, setPos] = useState(0);
  const [flipped, setFlipped] = useState(false);
  const [mastered, setMastered] = useState<Set<string>>(new Set());

  const byId = useMemo(() => new Map(cards.map((c) => [c.id, c])), [cards]);

  if (cards.length === 0) {
    return (
      <p className="rounded-2xl bg-white/70 p-6 text-slate-500">
        No flashcards for this module yet.
      </p>
    );
  }

  const done = mastered.size >= cards.length;
  const currentId = queue[pos];
  const card = currentId ? byId.get(currentId) : undefined;

  function advance(masteredThis: boolean) {
    if (!currentId) return;
    const nextMastered = new Set(mastered);
    let nextQueue = queue;
    if (masteredThis) {
      nextMastered.add(currentId);
    } else {
      // Re-queue this card at the end for another pass.
      nextQueue = [...queue, currentId];
    }
    setMastered(nextMastered);
    setFlipped(false);
    setQueue(nextQueue);
    setPos((p) => p + 1);
  }

  function restart() {
    setQueue(initial);
    setPos(0);
    setFlipped(false);
    setMastered(new Set());
  }

  if (done || !card) {
    return (
      <div className="animate-pop rounded-3xl border border-emerald-200 bg-emerald-50 p-8 text-center">
        <div className="text-4xl">🎉</div>
        <h3 className="mt-2 text-xl font-bold text-emerald-800">
          Deck complete — {cards.length} cards reviewed
        </h3>
        <p className="mt-1 text-emerald-700">Nice recall. Ready for the quiz?</p>
        <button
          onClick={restart}
          className="mt-4 rounded-xl border border-emerald-300 bg-white px-5 py-2 font-semibold text-emerald-700 hover:bg-emerald-100"
        >
          Review again
        </button>
      </div>
    );
  }

  const pct = Math.round((mastered.size / cards.length) * 100);

  return (
    <div>
      <div className="mb-3 flex items-center justify-between text-sm font-medium text-slate-500">
        <span>
          {card.profession ? "🎯 For your role" : "Concept"} · {mastered.size}/
          {cards.length} mastered
        </span>
        <span>{pct}%</span>
      </div>
      <div className="mb-4 h-2 w-full overflow-hidden rounded-full bg-slate-200">
        <div
          className="h-full rounded-full bg-gradient-to-r from-indigo-500 to-fuchsia-500 transition-all"
          style={{ width: `${pct}%` }}
        />
      </div>

      <div className="card-flip">
        <button
          onClick={() => setFlipped((f) => !f)}
          className="relative block h-64 w-full text-left"
          aria-label="Flip card"
        >
          <div className={`card-flip-inner relative h-full w-full ${flipped ? "is-flipped" : ""}`}>
            {/* Front */}
            <div className="card-face absolute inset-0 flex flex-col justify-between rounded-3xl border border-white/70 bg-white p-7 shadow-xl">
              <span className="text-xs font-bold uppercase tracking-widest text-indigo-400">
                Question
              </span>
              <p className="text-xl font-semibold text-slate-800">{card.front}</p>
              <span className="text-sm text-slate-400">Tap to flip ↻</span>
            </div>
            {/* Back */}
            <div className="card-face card-face-back absolute inset-0 flex flex-col justify-between rounded-3xl border border-indigo-200 bg-gradient-to-br from-indigo-50 to-fuchsia-50 p-7 shadow-xl">
              <span className="text-xs font-bold uppercase tracking-widest text-fuchsia-500">
                Answer
              </span>
              <p className="text-lg text-slate-800">{card.back}</p>
              <span className="text-sm text-slate-400">Tap to flip ↻</span>
            </div>
          </div>
        </button>
      </div>

      <div className="mt-5 grid grid-cols-2 gap-3">
        <button
          onClick={() => advance(false)}
          className="rounded-xl border border-slate-300 bg-white px-4 py-3 font-semibold text-slate-600 transition hover:bg-slate-50"
        >
          🔁 Review again
        </button>
        <button
          onClick={() => advance(true)}
          className="rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 px-4 py-3 font-semibold text-white shadow-lg transition hover:brightness-110"
        >
          ✅ Got it
        </button>
      </div>
    </div>
  );
}
