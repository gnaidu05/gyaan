import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Gyaan — Learn Claude, your way",
  description:
    "A personalized, gamified course that teaches you Claude with real examples from your own profession.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col text-slate-800">{children}</body>
    </html>
  );
}
