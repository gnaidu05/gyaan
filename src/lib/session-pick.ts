// Per-session content selection. Every module page render (force-dynamic, so
// every visit and every login) pulls a fresh, shuffled, difficulty-scaffolded
// subset from the larger content pool — the same login never sees a stale,
// identical set, and quiz answer positions are reshuffled too.

const DIFFICULTY_ORDER: Record<string, number> = {
  beginner: 0,
  intermediate: 1,
  advanced: 2,
};

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// Picks up to `count` items, spread evenly across whichever difficulty tiers
// are present in `pool`, then orders the result easy -> hard so a session
// warms up before it challenges — a small "professional teacher" scaffolding
// touch rather than a random jumble.
export function pickSession<T extends { id: string; difficulty: string }>(
  pool: T[],
  count: number,
): T[] {
  if (pool.length <= count) {
    return [...pool].sort(
      (a, b) => (DIFFICULTY_ORDER[a.difficulty] ?? 1) - (DIFFICULTY_ORDER[b.difficulty] ?? 1),
    );
  }

  const byTier = new Map<string, T[]>();
  for (const item of pool) {
    const list = byTier.get(item.difficulty) ?? [];
    list.push(item);
    byTier.set(item.difficulty, list);
  }
  for (const [tier, list] of byTier) byTier.set(tier, shuffle(list));

  const tiers = [...byTier.keys()].sort(
    (a, b) => (DIFFICULTY_ORDER[a] ?? 1) - (DIFFICULTY_ORDER[b] ?? 1),
  );
  const perTier = Math.ceil(count / tiers.length);
  let picked: T[] = [];
  for (const tier of tiers) {
    picked.push(...(byTier.get(tier) ?? []).slice(0, perTier));
  }
  picked = picked.slice(0, count);

  if (picked.length < count) {
    const chosenIds = new Set(picked.map((p) => p.id));
    const rest = shuffle(pool.filter((p) => !chosenIds.has(p.id)));
    picked = picked.concat(rest.slice(0, count - picked.length));
  }

  return picked.sort(
    (a, b) => (DIFFICULTY_ORDER[a.difficulty] ?? 1) - (DIFFICULTY_ORDER[b.difficulty] ?? 1),
  );
}

// Shuffles a quiz question's option order and remaps correct_index, so the
// right answer isn't always in the same slot from session to session.
export function shuffleOptions<T extends { options: string[]; correct_index: number }>(
  q: T,
): T {
  const indices = shuffle(q.options.map((_, i) => i));
  const options = indices.map((i) => q.options[i]);
  const correct_index = indices.indexOf(q.correct_index);
  return { ...q, options, correct_index };
}
