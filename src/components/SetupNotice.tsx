// Shown when Supabase env vars are missing so a fresh clone renders something
// helpful instead of throwing.
export default function SetupNotice() {
  return (
    <main className="flex-1 flex items-center justify-center px-4 py-16">
      <div className="max-w-xl rounded-3xl border border-white/60 bg-white/80 p-8 shadow-xl backdrop-blur">
        <div className="text-4xl">🔧</div>
        <h1 className="mt-3 text-2xl font-bold">Almost there — add your Supabase keys</h1>
        <p className="mt-2 text-slate-600">
          Gyaan needs a Supabase project to store accounts and progress. Copy{" "}
          <code className="rounded bg-slate-100 px-1.5 py-0.5">.env.example</code> to{" "}
          <code className="rounded bg-slate-100 px-1.5 py-0.5">.env.local</code> and fill in:
        </p>
        <ul className="mt-4 space-y-1 font-mono text-sm text-slate-700">
          <li>NEXT_PUBLIC_SUPABASE_URL</li>
          <li>NEXT_PUBLIC_SUPABASE_ANON_KEY</li>
        </ul>
        <p className="mt-4 text-slate-600">
          Then run the SQL in{" "}
          <code className="rounded bg-slate-100 px-1.5 py-0.5">supabase/migrations</code> and{" "}
          <code className="rounded bg-slate-100 px-1.5 py-0.5">supabase/seed.sql</code>, and
          restart <code className="rounded bg-slate-100 px-1.5 py-0.5">npm run dev</code>. Full
          steps are in the README.
        </p>
      </div>
    </main>
  );
}
