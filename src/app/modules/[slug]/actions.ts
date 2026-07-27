"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { QuizResult } from "@/components/Quiz";

const PASS_RATIO = 0.6;
const PERFECT_BONUS = 50;

// Records a quiz attempt, updates module progress, and awards points + badges.
// Idempotent on points: module-completion points are granted only on the first
// transition to "completed"; the perfect-score bonus only once per module.
export async function submitQuiz(
  moduleSlug: string,
  score: number,
  total: number,
  answers: number[],
): Promise<QuizResult> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Not authenticated");

  const { data: mod } = await supabase
    .from("modules")
    .select("id, slug, points_reward")
    .eq("slug", moduleSlug)
    .single();
  if (!mod) throw new Error("Module not found");

  const passed = total > 0 && score / total >= PASS_RATIO;
  const perfect = total > 0 && score === total;

  // Record the attempt.
  await supabase.from("quiz_attempts").insert({
    user_id: user.id,
    module_id: mod.id,
    score,
    total,
    answers,
  });

  // Was this module already completed before now?
  const { data: existing } = await supabase
    .from("module_progress")
    .select("id, status, best_score")
    .eq("user_id", user.id)
    .eq("module_id", mod.id)
    .maybeSingle();

  const wasCompleted = existing?.status === "completed";
  const nowCompleted = wasCompleted || passed;
  const bestScore = Math.max(existing?.best_score ?? 0, score);

  await supabase.from("module_progress").upsert(
    {
      user_id: user.id,
      module_id: mod.id,
      status: nowCompleted ? "completed" : "in_progress",
      best_score: bestScore,
      quiz_total: total,
      completed_at: nowCompleted ? new Date().toISOString() : null,
    },
    { onConflict: "user_id,module_id" },
  );

  let pointsAwarded = 0;

  // First-time completion → module points.
  if (passed && !wasCompleted) {
    pointsAwarded += mod.points_reward;
    await supabase.from("point_events").insert({
      user_id: user.id,
      delta: mod.points_reward,
      reason: "module_completed",
      module_id: mod.id,
    });
  }

  // Perfect score bonus, once per module.
  if (perfect) {
    const { data: priorPerfect } = await supabase
      .from("point_events")
      .select("id")
      .eq("user_id", user.id)
      .eq("module_id", mod.id)
      .eq("reason", "perfect_quiz")
      .maybeSingle();
    if (!priorPerfect) {
      pointsAwarded += PERFECT_BONUS;
      await supabase.from("point_events").insert({
        user_id: user.id,
        delta: PERFECT_BONUS,
        reason: "perfect_quiz",
        module_id: mod.id,
      });
    }
  }

  // ---- Badge evaluation ----
  const [{ count: totalModules }, { data: completedRows }, { data: ownedBadges }] =
    await Promise.all([
      supabase.from("modules").select("id", { count: "exact", head: true }),
      supabase
        .from("module_progress")
        .select("module_id")
        .eq("user_id", user.id)
        .eq("status", "completed"),
      supabase
        .from("user_badges")
        .select("badge:badges(slug)")
        .eq("user_id", user.id),
    ]);

  const completedCount = completedRows?.length ?? 0;
  const modCount = totalModules ?? 6;
  const owned = new Set(
    ((ownedBadges as unknown as { badge: { slug: string } }[]) ?? []).map(
      (r) => r.badge.slug,
    ),
  );

  const toAward: string[] = [];
  const want = (slug: string, cond: boolean) => {
    if (cond && !owned.has(slug)) toAward.push(slug);
  };

  want("first-steps", completedCount >= 1);
  want("streak-starter", completedCount >= 2);
  want("halfway-hero", completedCount >= Math.ceil(modCount / 2));
  want("claude-master", completedCount >= modCount);
  want("perfect-score", perfect);
  want("prompt-pro", perfect && mod.slug === "prompting");

  const newBadges: { name: string; icon: string }[] = [];
  if (toAward.length) {
    const { data: badgeRows } = await supabase
      .from("badges")
      .select("id, slug, name, icon")
      .in("slug", toAward);

    const rows = (badgeRows as { id: string; slug: string; name: string; icon: string }[]) ?? [];
    if (rows.length) {
      await supabase.from("user_badges").upsert(
        rows.map((b) => ({ user_id: user.id, badge_id: b.id })),
        { onConflict: "user_id,badge_id", ignoreDuplicates: true },
      );
      rows.forEach((b) => newBadges.push({ name: b.name, icon: b.icon }));
    }
  }

  // Fresh total.
  const { data: pts } = await supabase
    .from("point_events")
    .select("delta")
    .eq("user_id", user.id);
  const totalPoints = ((pts as { delta: number }[]) ?? []).reduce(
    (s, r) => s + r.delta,
    0,
  );

  revalidatePath("/dashboard");
  revalidatePath(`/modules/${moduleSlug}`);

  return {
    pointsAwarded,
    totalPoints,
    newBadges,
    moduleCompleted: nowCompleted,
  };
}
