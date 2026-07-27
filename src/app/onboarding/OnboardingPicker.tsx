"use client";

import { useState, useTransition } from "react";
import { PROFESSIONS } from "@/lib/professions";
import { saveProfession } from "./actions";

export default function OnboardingPicker() {
  const [selected, setSelected] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function submit() {
    if (!selected) return;
    const fd = new FormData();
    fd.set("profession", selected);
    startTransition(() => saveProfession(fd));
  }

  return (
    <div>
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {PROFESSIONS.map((p) => {
          const active = selected === p.key;
          return (
            <button
              key={p.key}
              type="button"
              onClick={() => setSelected(p.key)}
              className={`group rounded-3xl bg-gradient-to-br ${p.accent} p-[2px] text-left shadow-lg transition ${
                active ? "scale-[1.02] shadow-xl" : "opacity-90 hover:opacity-100"
              }`}
            >
              <div
                className={`flex h-full flex-col gap-1 rounded-3xl px-5 py-5 backdrop-blur ${
                  active ? "bg-white" : "bg-white/90"
                }`}
              >
                <div className="flex items-center justify-between">
                  <span className="text-3xl">{p.icon}</span>
                  {active && <span className="text-xl">✅</span>}
                </div>
                <span className="mt-1 text-lg font-bold text-slate-800">{p.label}</span>
                <span className="text-sm text-slate-500">{p.blurb}</span>
              </div>
            </button>
          );
        })}
      </div>

      <div className="mt-8 flex justify-center">
        <button
          onClick={submit}
          disabled={!selected || pending}
          className="rounded-2xl bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-8 py-3.5 text-lg font-bold text-white shadow-xl shadow-indigo-300/50 transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
        >
          {pending ? "Setting up your path…" : "Start my journey →"}
        </button>
      </div>
    </div>
  );
}
