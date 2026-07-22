// Auth-gated: must render per-request (reads cookies/session).
export const dynamic = "force-dynamic";

import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/config";
import SetupNotice from "@/components/SetupNotice";
import AuthForm from "./AuthForm";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string; mode?: string }>;
}) {
  if (!isSupabaseConfigured) return <SetupNotice />;

  const { next, mode } = await searchParams;

  // Already signed in? Skip the form.
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (user) redirect("/dashboard");

  return (
    <main className="flex-1 flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        <Link
          href="/"
          className="mb-6 flex items-center justify-center gap-2 text-2xl font-black tracking-tight"
        >
          <span className="text-3xl">🧠</span>
          <span className="bg-gradient-to-r from-indigo-600 to-fuchsia-600 bg-clip-text text-transparent">
            Gyaan
          </span>
        </Link>

        <div className="rounded-3xl border border-white/60 bg-white/80 p-8 shadow-xl shadow-indigo-200/40 backdrop-blur">
          <AuthForm defaultMode={mode === "signup" ? "signup" : "signin"} next={next ?? "/dashboard"} />
        </div>

        <p className="mt-6 text-center text-sm text-slate-500">
          Learn Claude with examples from your actual job.
        </p>
      </div>
    </main>
  );
}
