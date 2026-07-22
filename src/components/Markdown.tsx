import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

// Small styled markdown renderer for module teaching content.
export default function Markdown({ children }: { children: string }) {
  return (
    <div className="space-y-3 leading-relaxed text-slate-700">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          h1: (p) => <h1 className="text-2xl font-bold text-slate-900" {...p} />,
          h2: (p) => <h2 className="mt-4 text-xl font-bold text-slate-900" {...p} />,
          h3: (p) => <h3 className="mt-3 text-lg font-semibold text-slate-900" {...p} />,
          p: (p) => <p className="text-slate-700" {...p} />,
          ul: (p) => <ul className="list-disc space-y-1 pl-5" {...p} />,
          ol: (p) => <ol className="list-decimal space-y-1 pl-5" {...p} />,
          li: (p) => <li className="text-slate-700" {...p} />,
          strong: (p) => <strong className="font-semibold text-slate-900" {...p} />,
          code: (p) => (
            <code className="rounded bg-slate-100 px-1.5 py-0.5 font-mono text-sm text-indigo-700" {...p} />
          ),
          a: (p) => <a className="text-indigo-600 underline" {...p} />,
        }}
      >
        {children}
      </ReactMarkdown>
    </div>
  );
}
