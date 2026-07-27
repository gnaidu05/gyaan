import Anthropic from "@anthropic-ai/sdk";

// The live prompt-practice feature can be powered two ways:
//  1. BYOK — the learner supplies their own Anthropic API key (held in their
//     browser, passed per-request, never stored server-side).
//  2. An optional operator key in ANTHROPIC_API_KEY (a deployment can provide one).
// If neither is present, practice falls back to a free offline heuristic check.
export const isOperatorKeyConfigured = !!process.env.ANTHROPIC_API_KEY;

// Default to the most capable model; allow an override for cost/latency tuning.
export function getModel() {
  return process.env.ANTHROPIC_MODEL || "claude-opus-4-8";
}

// Resolve the key to use: the learner's own key wins, else the operator key.
export function resolveApiKey(userKey?: string | null): string | null {
  const k = userKey?.trim();
  if (k) return k;
  return process.env.ANTHROPIC_API_KEY || null;
}

export function getAnthropic(apiKey: string) {
  return new Anthropic({ apiKey });
}
