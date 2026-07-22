// Auth-gated: must render per-request (reads cookies/session).
export const dynamic = "force-dynamic";

import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getModuleDetail, getPointsTotal, getProfile } from "@/lib/data";
import { isSupabaseConfigured } from "@/lib/config";
import SetupNotice from "@/components/SetupNotice";
import AppHeader from "@/components/AppHeader";
import Markdown from "@/components/Markdown";
import ModuleWorkspace from "./ModuleWorkspace";
import { submitQuiz } from "./actions";

export default async function ModulePage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  if (!isSupabaseConfigured) return <SetupNotice />;

  const { slug } = await params;
  const profile = await getProfile();
  if (!profile) redirect("/login");
  if (!profile.onboarded) redirect("/onboarding");

  const [detail, points] = await Promise.all([
    getModuleDetail(slug, profile.profession),
    getPointsTotal(),
  ]);
  if (!detail) notFound();

  const { module, example, flashcards, questions, progress } = detail;

  // Bind the module slug so the client component gets an (score,total,answers) action.
  const boundSubmit = submitQuiz.bind(null, slug);

  return (
    <>
      <AppHeader points={points} profession={profile.profession} />
      <main className="flex-1 px-4 py-8">
        <div className="mx-auto max-w-3xl">
          <Link href="/dashboard" className="text-sm font-semibold text-slate-500 hover:text-slate-800">
            ← Back to dashboard
          </Link>

          <div className={`mt-4 overflow-hidden rounded-3xl bg-gradient-to-br ${module.accent ?? "from-indigo-500 to-fuchsia-500"} p-[2px] shadow-xl`}>
            <div className="rounded-3xl bg-white/95 px-7 py-6">
              <div className="flex items-center gap-3">
                <span className="text-4xl">{module.icon}</span>
                <div>
                  <h1 className="text-2xl font-black tracking-tight sm:text-3xl">
                    {module.title}
                  </h1>
                  {module.subtitle && (
                    <p className="text-slate-500">{module.subtitle}</p>
                  )}
                </div>
              </div>
              <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
                <span className="rounded-full bg-amber-100 px-3 py-1 font-semibold text-amber-700">
                  🪙 {module.points_reward} pts on completion
                </span>
                {progress?.status === "completed" && (
                  <span className="rounded-full bg-emerald-100 px-3 py-1 font-semibold text-emerald-700">
                    ✅ Completed{progress.best_score != null ? ` · best ${progress.best_score}/${progress.quiz_total}` : ""}
                  </span>
                )}
              </div>
            </div>
          </div>

          <div className="mt-6">
            <ModuleWorkspace
              learnContent={<Markdown>{module.core_content}</Markdown>}
              example={example}
              profession={profile.profession}
              flashcards={flashcards}
              questions={questions}
              onSubmitQuiz={boundSubmit}
            />
          </div>
        </div>
      </main>
    </>
  );
}
