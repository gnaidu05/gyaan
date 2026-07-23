// Free, offline prompt check used when no API key is available. It scores a
// prompt against the same qualities the lessons teach — context, a clear ask,
// output constraints, and an example/criterion — with no LLM call and no cost.
// Lower fidelity than a real Claude critique, but genuinely useful and instant.

type Check = {
  label: string;
  pass: boolean;
  good: string; // shown as a strength when it passes
  tip: string; // shown as an improvement when it fails
};

const IMPERATIVES =
  /\b(draft|write|summar(y|ize|ise)|analyz|analys|create|list|explain|review|compare|generate|rewrite|plan|outline|translate|classif|extract|brainstorm|critique|improve)\w*/i;

const FORMAT =
  /\b(format|bullet|bulleted|tone|concise|under \d+|less than \d+|no more than|table|steps|step-by-step|paragraph|email|subject line|word|words|sentence|sentences|section|headline|json|markdown)\b/i;

const EXAMPLE =
  /\b(for example|e\.?g\.?|such as|like this|similar to|make it (sound|feel|read)|in the style of|for instance)\b/i;

const CONTEXT =
  /\b(i'?m|i am|we'?re|we are|our|my|the (client|team|company|role|candidate|report|customer)|context|background|audience)\b/i;

export type HeuristicResult = {
  score: number;
  strengths: string[];
  improvements: string[];
};

export function heuristicGrade(prompt: string): HeuristicResult {
  const p = prompt.trim();
  const words = p.split(/\s+/).filter(Boolean).length;

  const checks: Check[] = [
    {
      label: "context",
      pass: CONTEXT.test(p) && words >= 12,
      good: "Gives Claude context about who you are and the situation, so it doesn't have to guess.",
      tip: "Add context — who you are, who it's for, and the goal. Claude answers far better when it isn't guessing.",
    },
    {
      label: "ask",
      pass: IMPERATIVES.test(p),
      good: "States a clear action you want Claude to take.",
      tip: "Lead with a clear instruction (e.g. 'Draft…', 'Summarize…', 'Compare…') so the task is unambiguous.",
    },
    {
      label: "format",
      pass: FORMAT.test(p),
      good: "Specifies the shape of the output — format, length, or tone.",
      tip: "Say what good output looks like: format, length, and tone (e.g. 'a 3-bullet summary, under 80 words, plain language').",
    },
    {
      label: "example",
      pass: EXAMPLE.test(p),
      good: "Anchors the result with an example or a concrete success criterion.",
      tip: "Give an example or a success criterion ('sounds human, not templated') to steer the result.",
    },
    {
      label: "focus",
      pass: words >= 8 && words <= 220,
      good: "Focused and specific without being a wall of text.",
      tip: words < 8
        ? "Too short to act on — add the specifics Claude needs."
        : "Quite long — tighten it to the essentials so the ask stays clear.",
    },
  ];

  const passed = checks.filter((c) => c.pass);
  const failed = checks.filter((c) => !c.pass);

  // Weighted-ish: each check worth 20, with a small floor so a real attempt
  // never reads as zero.
  const raw = Math.round((passed.length / checks.length) * 100);
  const score = Math.max(15, Math.min(100, raw));

  const strengths = (passed.length ? passed : checks.slice(0, 1)).slice(0, 3).map((c) => c.good);
  const improvements = (failed.length ? failed : [checks[3]]).slice(0, 3).map((c) => c.tip);

  return { score, strengths, improvements };
}
