import OpenAI from "openai"
import { createServiceClient } from "@/lib/supabase/service"
import { USER_ID } from "@/lib/operations/auth"

export type RecordLite = {
  id: string
  type: string
  title: string
  content: string
  source: string
  status: string | null
  created_at: string
  pinned: boolean
}

export type OperationLite = {
  id: string
  name: string
  description: string | null
  objectives: string | null
  directives: string | null
}

function getClient() {
  return new OpenAI({ apiKey: process.env.XAI_API_KEY!, baseURL: "https://api.x.ai/v1" })
}

/**
 * Pulls an operation and all of its non-archived records. Used by every
 * Eve-analyst endpoint so they share the exact same view of the data.
 */
export async function loadOperationContext(operationId: string): Promise<{
  operation: OperationLite
  records: RecordLite[]
} | null> {
  const supabase = createServiceClient()
  const [{ data: operation }, { data: records }] = await Promise.all([
    supabase
      .from("operations")
      .select("id, name, description, objectives, directives")
      .eq("id", operationId)
      .eq("user_id", USER_ID)
      .single(),
    supabase
      .from("operation_records")
      .select("id, type, title, content, source, status, created_at, pinned")
      .eq("operation_id", operationId)
      .eq("user_id", USER_ID)
      .is("archived_at", null)
      .order("created_at", { ascending: true }),
  ])
  if (!operation) return null
  return { operation, records: (records ?? []) as RecordLite[] }
}

/**
 * Renders the operation + records into a prompt-ready block that every
 * analyst task can feed to the model.
 */
export function formatRecordsForPrompt(
  operation: OperationLite,
  records: RecordLite[],
): string {
  const header = `OPERATION: ${operation.name}\n` +
    (operation.description ? `DESCRIPTION: ${operation.description}\n` : "") +
    (operation.objectives ? `OBJECTIVES: ${operation.objectives}\n` : "") +
    (operation.directives ? `DIRECTIVES: ${operation.directives}\n` : "")

  const body = records.length === 0
    ? "\n(No records yet.)"
    : "\n\nRECORDS:\n" + records.map((r, i) => (
        `\n[${i + 1}] ${r.title}\n` +
        `  type: ${r.type}${r.status ? ` · status: ${r.status}` : ""}${r.pinned ? " · pinned" : ""}\n` +
        `  source: ${r.source}\n` +
        `  ${r.content || "(no content)"}`
      )).join("\n")

  return header + body
}

/**
 * Runs Eve as an "operations analyst" on a shared operation context and
 * returns the raw markdown string she produced. The caller is responsible
 * for persisting it (usually to operation_briefs).
 */
export async function runAnalyst(opts: {
  systemPrompt: string
  context: string
  userTask: string
  model?: string
}): Promise<string> {
  const client = getClient()
  const res = await client.chat.completions.create({
    model: opts.model ?? "grok-4-fast-reasoning",
    messages: [
      { role: "system", content: opts.systemPrompt },
      { role: "user", content: `${opts.userTask}\n\n---\n\n${opts.context}` },
    ],
    max_tokens: 2048,
  })
  return res.choices[0]?.message?.content?.trim() ?? ""
}

/**
 * Upserts a brief row for (operation_id, kind). Kinds are:
 *   "summary" | "actions" | "contradictions" | "themes" | "next-steps"
 */
export async function saveBrief(operationId: string, kind: string, content: string) {
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operation_briefs")
    .upsert(
      { operation_id: operationId, user_id: USER_ID, kind, content, generated_at: new Date().toISOString() },
      { onConflict: "operation_id,kind" },
    )
    .select()
    .single()
  if (error) throw new Error(error.message)
  return data
}
