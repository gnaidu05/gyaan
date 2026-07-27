import Link from "next/link";
import { getProfession } from "@/lib/professions";

// Top bar for authenticated pages: brand, live points, profession, sign out.
export default function AppHeader({
  points,
  profession,
}: {
  points: number;
  profession: string | null;
}) {
  const prof = getProfession(profession);
  return (
    <header className="sticky top-0 z-20 border-b border-white/60 bg-white/70 backdrop-blur">
      <div className="mx-auto flex max-w-5xl items-center justify-between px-5 py-3">
        <Link href="/dashboard" className="flex items-center gap-2 text-xl font-black">
          <span className="text-2xl">🧠</span>
          <span className="bg-gradient-to-r from-indigo-600 to-fuchsia-600 bg-clip-text text-transparent">
            Gyaan
          </span>
        </Link>
        <div className="flex items-center gap-3">
          {prof && (
            <span className="hidden items-center gap-1 rounded-full bg-slate-100 px-3 py-1.5 text-sm font-semibold text-slate-600 sm:inline-flex">
              {prof.icon} {prof.label}
            </span>
          )}
          <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-100 px-3 py-1.5 text-sm font-bold text-amber-700">
            🪙 {points}
          </span>
          <form action="/auth/signout" method="post">
            <button className="rounded-full border border-slate-300 bg-white px-3 py-1.5 text-sm font-semibold text-slate-600 hover:bg-slate-50">
              Sign out
            </button>
          </form>
        </div>
      </div>
    </header>
  );
}
