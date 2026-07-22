// Auth-gated: must render per-request (reads cookies/session).
export const dynamic = "force-dynamic";

import Link from "next/link";
import { redirect } from "next/navigation";
import {
  getAllBadges,
  getEarnedBadges,
  getLearningPath,
  getPointsTotal,
  getProfile,
} from "@/lib/data";
import { isSupabaseConfigured } from "@/lib/config";
import SetupNotice from "@/components/SetupNotice";
import AppHeader from "@/components/AppHeader";
import { getProfession } from "@/lib/professions";

export default async function DashboardPage() {
  if (!isSupabaseConfigured) return <SetupNotice />;

  const profile = await getProfile();
  if (!profile) redirect("/login");
  if (!profile.onboarded) redirect("/onboarding");

  const [path, points, earned, allBadges] = await Promise.all([
    getLearningPath(),
    getPointsTotal(),
    getEarnedBadges(),
    getAllBadges(),
  ]);

  const prof = getProfession(profile.profession);
  const completed = path.filter((m) => m.progress?.status === "completed").length;
  const pct = path.length ? Math.round((completed / path.length) * 100) : 0;
  const earnedSlugs = new Set(earned.map((b) => b.slug));
  const firstName = profile.full_name?.split(" ")[0] ?? "there";

  return (
    <>
      <AppHeader points={points} profession={profile.profession} />
      <main className="flex-1 px-4 py-8">
        <div className="mx-auto max-w-5xl">
          {/* Greeting + stats */}
          <div className="flex flex-col gap-4 rounded-3xl border border-white/70 bg-white/80 p-6 shadow-lg backdrop-blur sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h1 className="text-2xl font-black tracking-tight sm:text-3xl">
                Welcome back, {firstName} 👋
              </h1>
              <p className="mt-1 text-slate-600">
                Your Claude course, tuned for{" "}
                <span className="font-semibold text-indigo-700">
                  {prof ? `${prof.icon} ${prof.label}` : "you"}
                </span>
                .
              </p>
            </div>
            <div className="flex gap-3">
              <Stat label="Points" value={`🪙 ${points}`} />
              <Stat label="Modules" value={`${completed}/${path.length}`} />
              <Stat label="Badges" value={`🏅 ${earned.length}`} />
            </div>
          </div>

          {/* Progress bar */}
          <div className="mt-5 rounded-3xl border border-white/70 bg-white/80 p-5 shadow-lg backdrop-blur">
            <div className="mb-2 flex items-center justify-between text-sm font-semibold text-slate-500">
              <span>Course progress</span>
              <span>{pct}%</span>
            </div>
            <div className="h-3 w-full overflow-hidden rounded-full bg-slate-200">
              <div
                className="h-full rounded-full bg-gradient-to-r from-indigo-500 via-fuchsia-500 to-rose-500 transition-all"
                style={{ width: `${pct}%` }}
              />
            </div>
          </div>

          {/* Learning path */}
          <h2 className="mt-8 mb-4 text-xl font-black tracking-tight">Your learning path</h2>
          <div className="grid gap-4 sm:grid-cols-2">
            {path.map((m, i) => {
              const done = m.progress?.status === "completed";
              const started = m.progress?.status === "in_progress";
              const locked = m.locked;
              const card = (
                <div
                  className={`group relative h-full overflow-hidden rounded-3xl bg-gradient-to-br ${m.accent ?? "from-indigo-500 to-fuchsia-500"} p-[2px] shadow-lg transition ${
                    locked ? "opacity-60" : "hover:-translate-y-0.5 hover:shadow-xl"
                  }`}
                >
                  <div className="flex h-full flex-col rounded-3xl bg-white p-5">
                    <div className="flex items-start justify-between">
                      <span className="text-3xl">{m.icon}</span>
                      {done && <span className="text-sm font-bold text-emerald-600">✅ Done</span>}
                      {started && !done && <span className="text-sm font-bold text-indigo-600">▶ In progress</span>}
                      {locked && <span className="text-sm">🔒</span>}
                    </div>
                    <p className="mt-2 text-xs font-bold uppercase tracking-widest text-slate-400">
                      Module {i + 1}
                    </p>
                    <h3 className="text-lg font-bold text-slate-900">{m.title}</h3>
                    {m.subtitle && <p className="mt-1 text-sm text-slate-500">{m.subtitle}</p>}
                    <div className="mt-4 flex items-center justify-between">
                      <span className="text-sm font-semibold text-amber-600">🪙 {m.points_reward} pts</span>
                      {!locked && (
                        <span className="text-sm font-bold text-indigo-600 group-hover:underline">
                          {done ? "Review" : started ? "Continue" : "Start"} →
                        </span>
                      )}
                      {locked && <span className="text-sm text-slate-400">Finish previous</span>}
                    </div>
                  </div>
                </div>
              );
              return locked ? (
                <div key={m.id} className="cursor-not-allowed" aria-disabled>
                  {card}
                </div>
              ) : (
                <Link key={m.id} href={`/modules/${m.slug}`}>
                  {card}
                </Link>
              );
            })}
          </div>

          {/* Badges */}
          <h2 className="mt-10 mb-4 text-xl font-black tracking-tight">Badges</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
            {allBadges.map((b) => {
              const has = earnedSlugs.has(b.slug);
              return (
                <div
                  key={b.slug}
                  title={b.description}
                  className={`flex flex-col items-center gap-1 rounded-2xl border p-4 text-center ${
                    has
                      ? "border-indigo-200 bg-white shadow-md"
                      : "border-slate-200 bg-slate-50 opacity-60"
                  }`}
                >
                  <span className={`text-3xl ${has ? "" : "grayscale"}`}>{b.icon}</span>
                  <span className="text-xs font-bold text-slate-700">{b.name}</span>
                  <span className="text-[11px] leading-tight text-slate-400">{b.description}</span>
                </div>
              );
            })}
            {allBadges.length === 0 && (
              <p className="col-span-full text-slate-400">
                Badges load once the seed data is in place.
              </p>
            )}
          </div>
        </div>
      </main>
    </>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-slate-50 px-4 py-2 text-center">
      <div className="text-lg font-black text-slate-800">{value}</div>
      <div className="text-xs font-semibold uppercase tracking-wide text-slate-400">{label}</div>
    </div>
  );
}
