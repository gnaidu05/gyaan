// Auth-gated: must render per-request (reads cookies/session).
export const dynamic = "force-dynamic";

import { redirect } from "next/navigation";
import { getProfile } from "@/lib/data";
import { isSupabaseConfigured } from "@/lib/config";
import SetupNotice from "@/components/SetupNotice";
import OnboardingPicker from "./OnboardingPicker";

export default async function OnboardingPage() {
  if (!isSupabaseConfigured) return <SetupNotice />;

  const profile = await getProfile();
  if (!profile) redirect("/login");
  if (profile.onboarded) redirect("/dashboard");

  return (
    <main className="flex-1 px-4 py-12">
      <div className="mx-auto max-w-4xl">
        <div className="text-center">
          <span className="text-4xl">👋</span>
          <h1 className="mt-3 text-3xl font-black tracking-tight sm:text-4xl">
            Which best describes your work?
          </h1>
          <p className="mx-auto mt-3 max-w-xl text-slate-600">
            We&apos;ll fill your course with real examples from this field. You can
            explore everything either way — this just picks the flavor of the
            examples.
          </p>
        </div>
        <div className="mt-10">
          <OnboardingPicker />
        </div>
      </div>
    </main>
  );
}
