// Per-feature rubric the grader scores a learner's prompt against. Keyed by
// modules.feature_area so each module's practice checks the skill it taught.
export const RUBRICS: Record<string, string[]> = {
  chat: [
    "Gives Claude enough context to act without guessing (who they are, the goal)",
    "Asks for one clear thing rather than several unrelated tasks",
    "Sets up a conversation they can refine, not a one-shot demand",
  ],
  prompting: [
    "Is specific about the desired output (format, length, tone, audience)",
    "Provides relevant context or constraints",
    "Shows an example or names a clear success criterion where useful",
  ],
  projects: [
    "Leverages reusable/persistent context rather than re-explaining everything",
    "Separates durable instructions from the one-off request",
    "Is specific about what the project knowledge should be used for",
  ],
  artifacts: [
    "Asks Claude to produce a concrete, editable artifact (doc, app, visual)",
    "Specifies the format and key requirements of the artifact",
    "Leaves room to iterate on the artifact rather than demanding perfection first try",
  ],
  tools: [
    "Makes clear what external information or action is needed",
    "Gives Claude what it needs to use a tool well (query, source, or target)",
    "States the goal so Claude can decide when to search/browse/act",
  ],
  workflows: [
    "Breaks a real multi-step task into something Claude can execute",
    "Chains context so each step builds on the last",
    "Defines what 'done' looks like for the overall workflow",
  ],
};

export const DEFAULT_RUBRIC = RUBRICS.prompting;

export function getRubric(featureArea: string): string[] {
  return RUBRICS[featureArea] ?? DEFAULT_RUBRIC;
}
