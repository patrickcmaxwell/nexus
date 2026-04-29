export const maxDuration = 60

import { NextRequest, NextResponse } from "next/server"
import { createServiceClient } from "@/lib/supabase/service"
import { isAuthed, USER_ID } from "@/lib/operations/auth"
import {
  formatRecordsForPrompt,
  loadOperationContext,
  runAnalyst,
  saveBrief,
} from "@/lib/operations/eve-analyst"

const KINDS = new Set(["summary", "actions", "contradictions", "themes", "next-steps"])

const EVE_SYSTEM = `You are Eve, the command intelligence for Nexus. You are analyzing one of the Director's operations. Be concise, specific, and direct. Use markdown: headings, bullet lists, bold for the key point in each item. No preamble, no apologies, no "let me know if…" ending. Write like an analyst reporting to a commander.`

const TASKS: Record<string, string> = {
  summary: "Produce a structured OPERATION BRIEF that summarizes the state of this operation across all its records. Use sections: Current State, Progress, Key Findings, Open Questions. Keep it under 400 words.",
  actions: "Extract every concrete action item, task, or todo buried in the records. Output as a markdown checklist. For each item, note which record it came from in parentheses. Group by obvious theme if the list is long. If there are no actions, say so plainly.",
  contradictions: "Find contradictions between records, unresolved questions that were raised but never answered, and areas where the records disagree with the stated OBJECTIVES or DIRECTIVES. Output as markdown sections: Contradictions, Open Questions, Misalignments. If none exist, say so plainly.",
  themes: "Cluster the records into 3-6 themes based on their content. For each theme, give a short name, a one-sentence summary, and list the records (by title) that belong to it. Output as markdown headings.",
  "next-steps": "Based on the operation's current state, propose 3-7 concrete next steps the Director should take. Rank them by impact. For each step, explain in one sentence why it matters now and which records support the recommendation.",
}

// GET — fetch all existing briefs for this operation
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const supabase = createServiceClient()
  const { data, error } = await supabase
    .from("operation_briefs")
    .select("id, kind, content, generated_at")
    .eq("operation_id", id)
    .eq("user_id", USER_ID)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  const byKind = Object.fromEntries((data ?? []).map(b => [b.kind, b]))
  return NextResponse.json(byKind)
}

// POST — regenerate one brief (body: { kind: "summary" | "actions" | ... })
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const { kind } = await req.json()
  if (!KINDS.has(kind)) return NextResponse.json({ error: "invalid kind" }, { status: 400 })

  const ctx = await loadOperationContext(id)
  if (!ctx) return NextResponse.json({ error: "Operation not found" }, { status: 404 })

  if (ctx.records.length === 0) {
    return NextResponse.json({ error: "No records in this operation yet." }, { status: 400 })
  }

  try {
    const content = await runAnalyst({
      systemPrompt: EVE_SYSTEM,
      context: formatRecordsForPrompt(ctx.operation, ctx.records),
      userTask: TASKS[kind],
    })
    if (!content) return NextResponse.json({ error: "Eve returned empty output" }, { status: 500 })
    const saved = await saveBrief(id, kind, content)
    return NextResponse.json(saved)
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Analyst call failed"
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}

// DELETE — clear a brief (body: { kind })
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!(await isAuthed())) return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  const { id } = await params
  const { kind } = await req.json()
  if (!KINDS.has(kind)) return NextResponse.json({ error: "invalid kind" }, { status: 400 })
  const supabase = createServiceClient()
  const { error } = await supabase
    .from("operation_briefs")
    .delete()
    .eq("operation_id", id)
    .eq("user_id", USER_ID)
    .eq("kind", kind)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ success: true })
}
