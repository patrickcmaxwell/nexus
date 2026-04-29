"use server"

import { createClient } from "@/lib/supabase/server"
import { revalidatePath } from "next/cache"

export async function addMission(formData: FormData) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: "Unauthorized" }

  const { error } = await supabase.from("missions").insert({
    user_id: user.id,
    name: formData.get("name") as string,
    location: formData.get("location") as string,
    status: formData.get("status") as string,
    threat_level: formData.get("threat_level") as string,
    suit: formData.get("suit") as string,
    summary: formData.get("summary") as string,
    mission_date: new Date().toISOString(),
  })

  if (error) return { error: error.message }
  revalidatePath("/dashboard/missions")
  revalidatePath("/dashboard")
  return { success: true }
}

export async function updateMissionStatus(id: string, status: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: "Unauthorized" }

  const { error } = await supabase
    .from("missions")
    .update({ status })
    .eq("id", id)
    .eq("user_id", user.id)

  if (error) return { error: error.message }
  revalidatePath("/dashboard/missions")
  revalidatePath("/dashboard")
  return { success: true }
}

export async function deleteMission(id: string) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: "Unauthorized" }

  const { error } = await supabase
    .from("missions")
    .delete()
    .eq("id", id)
    .eq("user_id", user.id)

  if (error) return { error: error.message }
  revalidatePath("/dashboard/missions")
  revalidatePath("/dashboard")
  return { success: true }
}
