"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";
import { useActionState } from "react";
import { signIn, signUp, type AuthState } from "./actions";

function SubmitButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full rounded-xl bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-4 py-3 font-semibold text-white shadow-lg shadow-indigo-300/50 transition hover:brightness-110 disabled:opacity-60"
    >
      {pending ? "Please wait…" : label}
    </button>
  );
}

export default function AuthForm({
  defaultMode,
  next,
}: {
  defaultMode: "signin" | "signup";
  next: string;
}) {
  const [mode, setMode] = useState<"signin" | "signup">(defaultMode);
  const action = mode === "signin" ? signIn : signUp;
  const [state, formAction] = useActionState<AuthState, FormData>(action, {});

  return (
    <div>
      <div className="mb-6 grid grid-cols-2 gap-1 rounded-xl bg-slate-100 p-1 text-sm font-semibold">
        <button
          onClick={() => setMode("signin")}
          className={`rounded-lg py-2 transition ${
            mode === "signin" ? "bg-white shadow text-indigo-700" : "text-slate-500"
          }`}
        >
          Log in
        </button>
        <button
          onClick={() => setMode("signup")}
          className={`rounded-lg py-2 transition ${
            mode === "signup" ? "bg-white shadow text-indigo-700" : "text-slate-500"
          }`}
        >
          Sign up
        </button>
      </div>

      <form action={formAction} className="space-y-4">
        <input type="hidden" name="next" value={next} />

        {mode === "signup" && (
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-600">
              Name
            </label>
            <input
              name="full_name"
              type="text"
              autoComplete="name"
              placeholder="Ada Lovelace"
              className="w-full rounded-xl border border-slate-200 bg-white px-4 py-2.5 outline-none focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200"
            />
          </div>
        )}

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-600">
            Email
          </label>
          <input
            name="email"
            type="email"
            required
            autoComplete="email"
            placeholder="you@work.com"
            className="w-full rounded-xl border border-slate-200 bg-white px-4 py-2.5 outline-none focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200"
          />
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-600">
            Password
          </label>
          <input
            name="password"
            type="password"
            required
            autoComplete={mode === "signin" ? "current-password" : "new-password"}
            placeholder="••••••••"
            className="w-full rounded-xl border border-slate-200 bg-white px-4 py-2.5 outline-none focus:border-indigo-400 focus:ring-2 focus:ring-indigo-200"
          />
        </div>

        {state.error && (
          <p className="rounded-lg bg-rose-50 px-3 py-2 text-sm text-rose-700">
            {state.error}
          </p>
        )}
        {state.message && (
          <p className="rounded-lg bg-emerald-50 px-3 py-2 text-sm text-emerald-700">
            {state.message}
          </p>
        )}

        <SubmitButton label={mode === "signin" ? "Log in" : "Create account"} />
      </form>
    </div>
  );
}
