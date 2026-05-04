import OpenAI from "openai"
import type { createServiceClient } from "@/lib/supabase/service"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

/**
 * Best-effort: extract durable memories from the most recent unsummarized
 * Eve history rows and insert them into `eve_memory`. Marks the rows as
 * summarized once processed. Used by both `/api/eve` (Grok) and
 * `/api/eve/local` (Ollama) so memory grows from any conversation source.
 */
export async function summarizeInBackground(
  supabase: ReturnType<typeof createServiceClient>
): Promise<void> {
  try {
    const { data: rows } = await supabase
      .from("eve_history")
      .select("id, role, content")
      .eq("user_id", USER_ID)
      .eq("summarized", false)
      .order("created_at", { ascending: true })
      .limit(60)
    if (!rows || rows.length < 10) return

    const transcript = rows.map(r => `${r.role === "user" ? "DIRECTOR" : "EVE"}: ${r.content}`).join("\n")
    const client = new OpenAI({ apiKey: process.env.XAI_API_KEY!, baseURL: "https://api.x.ai/v1" })
    const res = await client.chat.completions.create({
      model: "grok-3-mini",
      messages: [
        {
          role: "system",
          content: `Extract durable memories from this conversation as JSON array: [{"type":"fact|task|objective|preference","content":"string","importance":1-10,"tags":["string"]}]. Return ONLY the JSON array.`,
        },
        { role: "user", content: transcript },
      ],
      max_tokens: 1024,
    })

    const raw = res.choices[0]?.message?.content ?? "[]"
    const match = raw.match(/\[[\s\S]*\]/)
    const memories: Array<{ type: string; content: string; importance: number; tags: string[] }> = match ? JSON.parse(match[0]) : []

    if (memories.length > 0) {
      await supabase.from("eve_memory").insert(
        memories.map(m => ({
          user_id: USER_ID,
          type: m.type ?? "fact",
          content: m.content,
          priority: Math.min(10, Math.max(1, m.importance ?? 5)),
          source: "auto-summarize",
          is_active: true,
        }))
      )
    }

    await supabase.from("eve_history").update({ summarized: true }).in("id", rows.map(r => r.id))
  } catch {
    // Summarization is best-effort — never block the main response.
  }
}

/**
 * Fires the summarizer if the unsummarized count is at or above the threshold.
 * Default trigger is every 20 messages. Returns the current count for telemetry.
 */
export async function maybeSummarize(
  supabase: ReturnType<typeof createServiceClient>,
  threshold: number = 20
): Promise<number> {
  const { count } = await supabase
    .from("eve_history")
    .select("*", { count: "exact", head: true })
    .eq("user_id", USER_ID)
    .eq("summarized", false)
  const c = count ?? 0
  if (c >= threshold) {
    summarizeInBackground(supabase).catch(() => {})
  }
  return c
}
