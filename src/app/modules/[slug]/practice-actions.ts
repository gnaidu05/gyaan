"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { getAnthropic, getModel, resolveApiKey } from "@/lib/anthropic";
import { getRubric } from "@/lib/practice";
import { heuristicGrade } from "@/lib/practice-heuristic";

export type PracticeResult = {
  ok: boolean;
  error?: string;
  mode?: "live" | "heuristic"; // whether Claude graded it, or the free offline check did
  assistantResponse?: string | null; // Claude's answer to the prompt (live mode only)
  score?: number;
  strengths?: string[];
  improvements?: string[];
  pointsAwarded?: number;
  totalPoints?: number;
};

const FIRST_ATTEMPT_POINTS = 20;
const STRONG_PROMPT_BONUS = 30;
const STRONG_SCORE = 80;

// Grades a learner's prompt. If a key is available (the learner's own — passed
// in and used only for this request, never stored — or an operator key), Claude
// answers the prompt AND grades it. Otherwise a free offline heuristic scores it.
export async function submitPractice(
  moduleSlug: string,
  scenario: string,
  userPrompt: string,
  userApiKey?: string,
): Promise<PracticeResult> {
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

  const apiKey = resolveApiKey(userApiKey);

  let mode: "live" | "heuristic";
  let assistantResponse: string | null = null;
  let score: number;
  let strengths: string[];
  let improvements: string[];

  if (apiKey) {
    // ---- Live grading via Claude ----
    const rubric = getRubric(mod.feature_area);
    const system = [
      "You are a professional teacher of Claude — patient, specific, and genuinely invested in the learner improving, like a good coding-bootcamp instructor doing office hours.",
      "You will be given a SCENARIO from the learner's job and the PROMPT they wrote to hand to Claude for it.",
      "Do two things and return them as JSON:",
      "1. assistant_response: answer the learner's prompt exactly as Claude would if they sent it — this shows them what their prompt actually produces. Keep it realistic but concise (a few short paragraphs at most).",
      `2. Grade their PROMPT for this lesson ("${mod.title}") against these criteria:`,
      ...rubric.map((r, i) => `   ${i + 1}. ${r}`),
      "Give a score from 0-100, 2-3 specific strengths, and 2-3 concrete, actionable improvements.",
      "Write like a teacher giving real feedback, not a form validator: warm, direct, and specific to what THIS learner wrote — reference their actual words, not generic advice. Judge the prompt, not the scenario.",
    ].join("\n");

    try {
      // The key is used only to construct this client and is never persisted or logged.
      const message = await getAnthropic(apiKey).messages.create({
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
      const parsed = JSON.parse(textBlock.text) as {
        assistant_response: string;
        score: number;
        strengths: string[];
        improvements: string[];
      };
      mode = "live";
      assistantResponse = parsed.assistant_response;
      score = Math.max(0, Math.min(100, Math.round(parsed.score)));
      strengths = parsed.strengths;
      improvements = parsed.improvements;
    } catch (e) {
      const msg = e instanceof Error ? e.message : "";
      // Friendly message for the most common BYOK failure: a bad/insufficient key.
      if (/401|authentication|invalid x-api-key|api key/i.test(msg)) {
        return {
          ok: false,
          error:
            "That API key was rejected. Check it in your Anthropic console, or clear it to use the free offline check.",
        };
      }
      if (/credit|billing|quota|insufficient/i.test(msg)) {
        return {
          ok: false,
          error:
            "Your Anthropic account is out of credit. Top up in the console, or clear your key to use the free offline check.",
        };
      }
      return {
        ok: false,
        error: msg ? `Grading failed: ${msg}` : "Grading failed. Try again.",
      };
    }
  } else {
    // ---- Free offline heuristic ----
    const h = heuristicGrade(prompt);
    mode = "heuristic";
    score = h.score;
    strengths = h.strengths;
    improvements = h.improvements;
  }

  // Persist the attempt.
  await supabase.from("practice_attempts").insert({
    user_id: user.id,
    module_id: mod.id,
    prompt,
    ai_response: assistantResponse,
    score,
    strengths,
    improvements,
  });

  // Points: reward the first practice per module, plus a one-time strong-prompt bonus.
  let pointsAwarded = 0;

  const { count: priorAttempts } = await supabase
    .from("practice_attempts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id)
    .eq("module_id", mod.id);

  if ((priorAttempts ?? 0) <= 1) {
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
    mode,
    assistantResponse,
    score,
    strengths,
    improvements,
    pointsAwarded,
    totalPoints,
  };
}
