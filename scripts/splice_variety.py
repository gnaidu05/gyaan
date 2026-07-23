#!/usr/bin/env python3
"""One-time build script: splices the agent-authored flashcards_variety.sql and
quiz_variety.sql into supabase/seed.sql (replacing the old, smaller sections),
then regenerates supabase/setup.sql. Not part of the app — a repo maintenance
tool, run once when refreshing the content pool.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "supabase" / "seed.sql"
FLASHCARDS_NEW = ROOT / "supabase" / "parts" / "flashcards_variety.sql"
QUIZ_NEW = ROOT / "supabase" / "parts" / "quiz_variety.sql"
SETUP = ROOT / "supabase" / "setup.sql"

FLASHCARDS_HEADER = "-- ===========================================================================\n-- FLASHCARDS"
QUIZ_HEADER = "-- ===========================================================================\n-- QUIZ QUESTIONS"
BADGES_HEADER = "-- ===========================================================================\n-- BADGES"

def section_bounds(src: str, start_marker: str, end_marker: str) -> tuple[int, int]:
    start = src.index(start_marker)
    end = src.index(end_marker)
    return start, end

def main():
    seed = SEED.read_text()
    flashcards_new = FLASHCARDS_NEW.read_text().strip() + "\n"
    quiz_new = QUIZ_NEW.read_text().strip() + "\n"

    fc_start, fc_end = section_bounds(seed, FLASHCARDS_HEADER, QUIZ_HEADER)
    fc_new_section = (
        FLASHCARDS_HEADER
        + "  (27 per module: 9 generic across 3 difficulty tiers + 3 per profession x 6)\n"
        + "-- ===========================================================================\n\n"
        + flashcards_new
        + "\n"
    )
    seed = seed[:fc_start] + fc_new_section + seed[fc_end:]

    qz_start, qz_end = section_bounds(seed, QUIZ_HEADER, BADGES_HEADER)
    qz_new_section = (
        QUIZ_HEADER
        + "  (27 per module: 9 generic across 3 difficulty tiers + 3 per profession x 6)\n"
        + "-- ===========================================================================\n\n"
        + quiz_new
        + "\n"
    )
    seed = seed[:qz_start] + qz_new_section + seed[qz_end:]

    SEED.write_text(seed)
    print(f"seed.sql updated ({len(seed)} bytes)")

    # Regenerate the one-paste setup.sql
    parts = [
        "-- ============================================================================\n"
        "-- Gyaan — ONE-PASTE setup for the Supabase SQL Editor.\n"
        "-- Paste this whole file and Run. It creates the schema, RLS, the practice\n"
        "-- table, and loads the full curriculum. Safe to re-run (seed clears content).\n"
        "-- Generated from supabase/migrations/*.sql + supabase/seed.sql — do not edit here.\n"
        "-- ============================================================================\n",
    ]
    for label, path in [
        ("0001_schema.sql", ROOT / "supabase/migrations/0001_schema.sql"),
        ("0002_practice.sql", ROOT / "supabase/migrations/0002_practice.sql"),
        ("0003_variety.sql", ROOT / "supabase/migrations/0003_variety.sql"),
        ("seed.sql", SEED),
    ]:
        parts.append(f"\n-- ===== {label} =====\n")
        parts.append(path.read_text())

    SETUP.write_text("".join(parts))
    print(f"setup.sql regenerated ({SETUP.stat().st_size} bytes)")

if __name__ == "__main__":
    main()
