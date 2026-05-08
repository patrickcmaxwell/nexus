import OpenAI from "openai"
import { createServiceClient } from "@/lib/supabase/service"
import { USER_ID } from "@/lib/operations/auth"

/**
 * Runs a long-form research job on behalf of the Director. Called from a
 * Next.js `after()` hook so it survives past the request that queued it.
 *
 * Flow:
 *  1. Mark the job "running".
 *  2. Ask the model to produce a structured dossier, using the parent
 *     record's title+content as the research brief.
 *  3. Parse the dossier's sections into individual child records under the
 *     parent record so both Eve and the Director can recall them later.
 *  4. Write a final "Research Summary" child record.
 *  5. Mark the job "completed" (or "failed" with the error string).
 *
 * If anything throws, the job is marked failed with a readable error so the
 * UI can surface it. Eve's conversation flow can also pick these up because
 * research_jobs is queryable.
 */
export async function runResearchJob(jobId: string) {
  const supabase = createServiceClient()

  // 1. Pull the job + parent record
  const { data: job } = await supabase
    .from("research_jobs")
    .select("*")
    .eq("id", jobId)
    .single()

  if (!job) return

  const { data: parent } = await supabase
    .from("operation_records")
    .select("id, operation_id, title, content, type")
    .eq("id", job.record_id)
    .single()

  if (!parent) {
    await supabase
      .from("research_jobs")
      .update({ status: "failed", error: "Parent record missing", completed_at: new Date().toISOString() })
      .eq("id", jobId)
    return
  }

  // 2. Mark the job running so the UI shows progress
  await supabase
    .from("research_jobs")
    .update({
      status: "running",
      started_at: new Date().toISOString(),
      progress_note: "Eve is researching…",
    })
    .eq("id", jobId)

  try {
    const client = new OpenAI({ apiKey: process.env.XAI_API_KEY!, baseURL: "https://api.x.ai/v1" })

    const prompt = job.prompt || `${parent.title}\n\n${parent.content || ""}`.trim()
    const model = job.model || "grok-4-fast-reasoning"

    // 3. Ask the model for a dossier in a strict JSON shape we can split
    //    into child records. JSON mode is the easiest way to get stable
    //    structure out of research.
    const res = await client.chat.completions.create({
      model,
      messages: [
        {
          role: "system",
          content: `You are Eve, acting as a senior research analyst for the user of Nexus. You will produce a structured JSON dossier on the given topic. Be thorough, specific, and cite concrete facts. Do not fabricate sources.

Return ONLY valid JSON matching this TypeScript type:
{
  "summary": string,                  // 2-3 paragraph overall summary in markdown
  "findings": Array<{
    "title": string,                  // short heading (under 60 chars)
    "body": string,                   // markdown, 1-4 paragraphs, with any inline sources as [name](url)
    "type": "finding" | "intel" | "note" | "data" | "alert"  // one of these
  }>,
  "questions": string[]               // open questions worth investigating further
}

Aim for 4-8 findings. Prioritize unique insights over restating the question.`,
        },
        { role: "user", content: `RESEARCH TOPIC:\n${prompt}` },
      ],
      response_format: { type: "json_object" },
      max_tokens: 4096,
    })

    const raw = res.choices[0]?.message?.content ?? "{}"
    const dossier: {
      summary?: string
      findings?: Array<{ title: string; body: string; type: string }>
      questions?: string[]
    } = JSON.parse(raw)

    const now = new Date().toISOString()
    const findings = Array.isArray(dossier.findings) ? dossier.findings : []
    const questions = Array.isArray(dossier.questions) ? dossier.questions : []

    // 4a. Summary child record (always first in children list)
    if (dossier.summary && dossier.summary.trim().length > 0) {
      await supabase.from("operation_records").insert({
        operation_id: parent.operation_id,
        user_id: USER_ID,
        parent_record_id: parent.id,
        title: "Research Summary",
        content: dossier.summary.trim(),
        type: "note",
        source: `research:${model}`,
        priority: "normal",
      })
    }

    // 4b. One child record per finding
    for (const f of findings) {
      if (!f?.title || !f?.body) continue
      const type = ["finding", "intel", "note", "data", "alert"].includes(f.type) ? f.type : "finding"
      await supabase.from("operation_records").insert({
        operation_id: parent.operation_id,
        user_id: USER_ID,
        parent_record_id: parent.id,
        title: f.title.slice(0, 140),
        content: f.body,
        type,
        source: `research:${model}`,
        priority: "normal",
      })
    }

    // 4c. One "Open Questions" child if any
    if (questions.length > 0) {
      const body = questions.map(q => `- ${q}`).join("\n")
      await supabase.from("operation_records").insert({
        operation_id: parent.operation_id,
        user_id: USER_ID,
        parent_record_id: parent.id,
        title: "Open Questions",
        content: body,
        type: "note",
        source: `research:${model}`,
        priority: "normal",
      })
    }

    // 5. Mark completed
    await supabase
      .from("research_jobs")
      .update({
        status: "completed",
        completed_at: now,
        result_summary: dossier.summary ?? null,
        findings_count: findings.length,
        progress_note: `Delivered ${findings.length} findings${questions.length ? ` and ${questions.length} open questions` : ""}.`,
      })
      .eq("id", jobId)
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Research job failed"
    await supabase
      .from("research_jobs")
      .update({ status: "failed", error: msg, completed_at: new Date().toISOString() })
      .eq("id", jobId)
  }
}
