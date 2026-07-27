import Link from "next/link";
import { PROFESSIONS } from "@/lib/professions";

export default function Home() {
  return (
    <main className="flex-1">
      {/* Nav */}
      <header className="mx-auto flex max-w-6xl items-center justify-between px-6 py-6">
        <div className="flex items-center gap-2 text-2xl font-black tracking-tight">
          <span className="text-3xl">🧠</span>
          <span className="bg-gradient-to-r from-indigo-600 to-fuchsia-600 bg-clip-text text-transparent">
            Gyaan
          </span>
        </div>
        <nav className="flex items-center gap-3">
          <Link href="/login" className="px-4 py-2 font-semibold text-slate-600 hover:text-slate-900">
            Log in
          </Link>
          <Link
            href="/login?mode=signup"
            className="rounded-xl bg-slate-900 px-4 py-2 font-semibold text-white shadow-lg transition hover:bg-slate-800"
          >
            Get started
          </Link>
        </nav>
      </header>

      {/* Hero */}
      <section className="mx-auto max-w-6xl px-6 pt-10 pb-16 text-center">
        <span className="inline-block rounded-full border border-indigo-200 bg-white/70 px-4 py-1.5 text-sm font-semibold text-indigo-700 backdrop-blur">
          ✨ Learn Claude, personalized to your job
        </span>
        <h1 className="mx-auto mt-6 max-w-3xl text-5xl font-black leading-tight tracking-tight sm:text-6xl">
          Master Claude with examples from{" "}
          <span className="bg-gradient-to-r from-indigo-600 via-fuchsia-600 to-rose-500 bg-clip-text text-transparent">
            your own profession
          </span>
        </h1>
        <p className="mx-auto mt-6 max-w-2xl text-lg text-slate-600">
          Gyaan teaches you the full surface of Claude — chat, prompting, projects,
          artifacts, tool use — through bite-sized flashcards and quizzes. Every example
          is drawn from real workflows in <em>your</em> field, not a generic tutorial.
        </p>
        <div className="mt-8 flex flex-wrap items-center justify-center gap-3">
          <Link
            href="/login?mode=signup"
            className="rounded-2xl bg-gradient-to-r from-indigo-600 to-fuchsia-600 px-7 py-3.5 text-lg font-bold text-white shadow-xl shadow-indigo-300/50 transition hover:brightness-110"
          >
            Start learning free
          </Link>
          <Link
            href="/login"
            className="rounded-2xl border border-slate-300 bg-white/70 px-7 py-3.5 text-lg font-bold text-slate-700 backdrop-blur transition hover:bg-white"
          >
            I have an account
          </Link>
        </div>
      </section>

      {/* Professions */}
      <section className="mx-auto max-w-6xl px-6 pb-16">
        <p className="mb-6 text-center text-sm font-semibold uppercase tracking-widest text-slate-400">
          Pick your lane at signup
        </p>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
          {PROFESSIONS.map((p) => (
            <div
              key={p.key}
              className={`rounded-2xl bg-gradient-to-br ${p.accent} p-[1.5px] shadow-lg`}
            >
              <div className="flex h-full flex-col items-center gap-2 rounded-2xl bg-white/90 px-3 py-5 text-center backdrop-blur">
                <span className="text-3xl">{p.icon}</span>
                <span className="text-sm font-bold text-slate-800">{p.label}</span>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* How it works */}
      <section className="mx-auto max-w-6xl px-6 pb-24">
        <div className="grid gap-5 md:grid-cols-3">
          {[
            {
              icon: "🎯",
              title: "Tell us your role",
              body: "A 20-second onboarding routes you into a learning path built around your day-to-day.",
            },
            {
              icon: "🃏",
              title: "Flip & quiz",
              body: "Interactive flashcards and scored quizzes make each Claude concept stick — no walls of text.",
            },
            {
              icon: "🏆",
              title: "Earn brownie points",
              body: "Complete modules to rack up points and unlock badges as you level up.",
            },
          ].map((f) => (
            <div
              key={f.title}
              className="rounded-3xl border border-white/60 bg-white/80 p-6 shadow-lg backdrop-blur"
            >
              <div className="text-3xl">{f.icon}</div>
              <h3 className="mt-3 text-lg font-bold">{f.title}</h3>
              <p className="mt-1 text-slate-600">{f.body}</p>
            </div>
          ))}
        </div>
      </section>

      <footer className="border-t border-white/60 py-8 text-center text-sm text-slate-500">
        Gyaan · An open-source LMS for learning Claude
      </footer>
    </main>
  );
}
