"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { getAnthropic, getModel, isAnthropicConfigured } from "@/lib/anthropic";
import { getRubric } from "@/lib/practice";

export type PracticeResult = {
  ok: boolean;
  error?: string;
  assistantResponse?: string;
  score?: number;
  strengths?: string[];
  improvements?: string[];
  pointsAwarded?: number;
  totalPoints?: number;
};

const FIRST_ATTEMPT_POINTS = 20;
const STRONG_PROMPT_BONUS = 30;
const STRONG_SCORE = 80;

// Runs the learner's prompt through Claude: Claude answers the prompt AND grades
// it against the module's rubric, returned as one structured JSON object.
export async function submitPractice(
  moduleSlug: string,
  scenario: string,
  userPrompt: string,
): Promise<PracticeResult> {
  if (!isAnthropicConfigured) {
    return { ok: false, error: "Live practice isn't configured on this server." };
  }
  const prompt = userPrompt.trim();
  if (prompt.length < 10) {
    return { ok: false, error: "Write a longer prompt to get useful feedback." };
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { ok: false, error: "Not authenticated." };

  const { data: mod } = await supabase
    .from("modules")
    .select("id, slug, title, feature_area")
    .eq("slug", moduleSlug)
    .single();
  if (!mod) return { ok: false, error: "Module not found." };

  const rubric = getRubric(mod.feature_area);

  const system = [
    "You are a friendly prompt-writing coach inside a course that teaches people to use Claude.",
    "You will be given a SCENARIO from the learner's job and the PROMPT they wrote to hand to Claude for it.",
    "Do two things and return them as JSON:",
    "1. assistant_response: answer the learner's prompt exactly as Claude would if they sent it — this shows them what their prompt actually produces. Keep it realistic but concise (a few short paragraphs at most).",
    `2. Grade their PROMPT for this lesson ("${mod.title}") against these criteria:`,
    ...rubric.map((r, i) => `   ${i + 1}. ${r}`),
    "Give a score from 0-100, 2-3 specific strengths, and 2-3 concrete, actionable improvements.",
    "Be encouraging and concrete. Judge the prompt, not the scenario.",
  ].join("\n");

  const anthropic = getAnthropic();

  let parsed: {
    assistant_response: string;
    score: number;
    strengths: string[];
    improvements: string[];
  };

  try {
    const message = await anthropic.messages.create({
      model: getModel(),
      max_tokens: 2048,
      system,
      messages: [
        {
          role: "user",
          content: `SCENARIO:\n${scenario}\n\nPROMPT THE LEARNER WROTE:\n${prompt}`,
        },
      ],
      output_config: {
        format: {
          type: "json_schema",
          schema: {
            type: "object",
            properties: {
              assistant_response: { type: "string" },
              score: { type: "integer" },
              strengths: { type: "array", items: { type: "string" } },
              improvements: { type: "array", items: { type: "string" } },
            },
            required: [
              "assistant_response",
              "score",
              "strengths",
              "improvements",
            ],
            additionalProperties: false,
          },
        },
      },
    });

    const textBlock = message.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      return { ok: false, error: "No response from the model. Try again." };
    }
    parsed = JSON.parse(textBlock.text);
  } catch (e) {
    return {
      ok: false,
      error:
        e instanceof Error
          ? `Grading failed: ${e.message}`
          : "Grading failed. Try again.",
    };
  }

  const score = Math.max(0, Math.min(100, Math.round(parsed.score)));

  // Persist the attempt.
  await supabase.from("practice_attempts").insert({
    user_id: user.id,
    module_id: mod.id,
    prompt,
    ai_response: parsed.assistant_response,
    score,
    strengths: parsed.strengths,
    improvements: parsed.improvements,
  });

  // Points: reward the first practice per module, plus a one-time strong-prompt bonus.
  let pointsAwarded = 0;

  const { count: priorAttempts } = await supabase
    .from("practice_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .eq("module_id", mod.id);

  if ((priorAttempts ?? 0) <= 1) {
    // <=1 because the row we just inserted is already counted.
    pointsAwarded += FIRST_ATTEMPT_POINTS;
    await supabase.from("point_events").insert({
      user_id: user.id,
      delta: FIRST_ATTEMPT_POINTS,
      reason: "practice_attempt",
      module_id: mod.id,
    });
  }

  if (score >= STRONG_SCORE) {
    const { data: priorStrong } = await supabase
      .from("point_events")
      .select("id")
      .eq("user_id", user.id)
      .eq("module_id", mod.id)
      .eq("reason", "strong_prompt")
      .maybeSingle();
    if (!priorStrong) {
      pointsAwarded += STRONG_PROMPT_BONUS;
      await supabase.from("point_events").insert({
        user_id: user.id,
        delta: STRONG_PROMPT_BONUS,
        reason: "strong_prompt",
        module_id: mod.id,
      });
    }
  }

  const { data: pts } = await supabase
    .from("point_events")
    .select("delta")
    .eq("user_id", user.id);
  const totalPoints = ((pts as { delta: number }[]) ?? []).reduce(
    (s, r) => s + r.delta,
    0,
  );

  if (pointsAwarded > 0) revalidatePath("/dashboard");

  return {
    ok: true,
    assistantResponse: parsed.assistant_response,
    score,
    strengths: parsed.strengths,
    improvements: parsed.improvements,
    pointsAwarded,
    totalPoints,
  };
}
