import Anthropic from "@anthropic-ai/sdk";

// The live prompt-practice feature calls Claude to answer the learner's prompt
// and grade it. It's optional: without a key, the Practice tab shows a notice
// instead of crashing (same graceful-degradation pattern as Supabase config).
export const isAnthropicConfigured = !!process.env.ANTHROPIC_API_KEY;

// Default to the most capable model; allow an override for cost/latency tuning.
export function getModel() {
  return process.env.ANTHROPIC_MODEL || "claude-opus-4-8";
}

export function getAnthropic() {
  return new Anthropic(); // reads ANTHROPIC_API_KEY from the environment
}
