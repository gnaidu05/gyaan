"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { PROFESSION_KEYS } from "@/lib/professions";

export async function saveProfession(formData: FormData) {
  const profession = String(formData.get("profession") || "");
  if (!PROFESSION_KEYS.includes(profession)) {
    return; // invalid; the form only submits known keys
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  await supabase
    .from("profiles")
    .update({ profession, onboarded: true, updated_at: new Date().toISOString() })
    .eq("id", user.id);

  redirect("/dashboard");
}
