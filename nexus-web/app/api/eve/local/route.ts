export const maxDuration = 60

import { createServiceClient } from "@/lib/supabase/service"
import { cookies } from "next/headers"
import { getLocalClient, OLLAMA_MODEL } from "@/lib/llm/local"
import { maybeSummarize } from "@/lib/eve/summarize"
import { extractMentions } from "@/lib/mentions/parse"
import { buildMentionsBlock } from "@/lib/mentions/context"
import OpenAI from "openai"

const USER_ID = "e9d9a15b-0e5a-4631-9b50-6225ee03a44f"

async function checkAuth(req: Request) {
  const supabase = createServiceClient()
  const bearer = req.headers.get("Authorization")
  const bearerId = bearer?.startsWith("Bearer ") ? bearer.slice(7) : null
  if (bearerId) {
    const { data } = await supabase.from("security_sessions").select("id, expires_at, invalidated").eq("id", bearerId).single()
    if (data && !data.invalidated && new Date(data.expires_at) > new Date()) return true
  }
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value
  if (!sessionId) return false
  const { data } = await supabase.from("security_sessions").select("id, expires_at").eq("id", sessionId).single()
  if (!data) return false
  return new Date(data.expires_at) > new Date()
}

// A leaner system prompt than /api/eve — small local models choke on 2KB
// of directives and lose track of the user's actual message. Identity +
// memory bank only; no tool-calling instructions, since this endpoint
// does not run the tool loop.
function buildLocalPrompt(memories: Array<{ type: string; content: string; priority: number }>): string {
  const base = `You are Eve, the private AI command intelligence of Patrick Maxwell, operating inside the Nexus command platform. Address Patrick as "sir" or "Director." Be direct, sharp, and efficient. Dry wit is permitted. Do not over-explain. Keep responses short — you are speaking aloud, not writing a report.`
  if (!memories.length) return base
  const top = memories.slice(0, 12).map(m => `- ${m.content}`).join("\n")
  return `${base}\n\nMEMORY BANK (treat as ground truth):\n${top}`
}

export async function POST(req: Request) {
  if (!await checkAuth(req)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { "Content-Type": "application/json" } })
  }

  const { userMessage, conversationId, source = "floating", model, stream, images } = await req.json()
  if (!userMessage) {
    return new Response(JSON.stringify({ error: "Missing userMessage" }), { status: 400, headers: { "Content-Type": "application/json" } })
  }
  const wantsStream = stream === true
  // images: optional array of base64-encoded image strings (no data URI prefix
  // needed). When present, the user message is sent as multimodal content
  // and the model defaults to llava:7b unless explicitly overridden.
  const hasImages = Array.isArray(images) && images.length > 0

  const supabase = createServiceClient()

  const { data: memories } = await supabase
    .from("eve_memory")
    .select("type, content, priority")
    .eq("user_id", USER_ID)
    .eq("is_active", true)
    .order("priority", { ascending: false })
    .limit(40)

  let systemPrompt = buildLocalPrompt(memories ?? [])

  // Resolve @[label](type:id) tokens in the user message into a context block
  // (same behavior as /api/eve) so the local model can ground references to
  // operations, agents, records, etc. without firing tool calls.
  const mentionTokens = extractMentions(userMessage)
  if (mentionTokens.length > 0) {
    const mentionsBlock = await buildMentionsBlock(supabase, USER_ID, mentionTokens)
    if (mentionsBlock) systemPrompt = `${systemPrompt}\n\n${mentionsBlock}`
  }

  // Resolve conversation thread
  let activeConversationId: string | null = conversationId ?? null
  if (!activeConversationId) {
    const title = source === "lumen" ? "Lumen Local" : "Local Brain"
    const { data: existing } = await supabase
      .from("eve_conversations")
      .select("id")
      .eq("user_id", USER_ID)
      .eq("source", source)
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle()
    if (existing) {
      activeConversationId = existing.id
    } else {
      const { data: newConv } = await supabase
        .from("eve_conversations")
        .insert({ user_id: USER_ID, title, source })
        .select("id")
        .single()
      activeConversationId = newConv?.id ?? null
    }
  }

  // Load prior history for context
  const { data: history } = activeConversationId ? await supabase
    .from("eve_history")
    .select("role, content")
    .eq("user_id", USER_ID)
    .eq("conversation_id", activeConversationId)
    .order("created_at", { ascending: true })
    .limit(40) : { data: [] }

  // Persist the user message
  if (activeConversationId) {
    await supabase.from("eve_history").insert({
      user_id: USER_ID,
      conversation_id: activeConversationId,
      role: "user",
      content: userMessage,
      summarized: false,
    })
    await supabase.from("eve_conversations")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", activeConversationId)
      .eq("user_id", USER_ID)
  }

  // Build the user turn — multimodal if images present, plain string otherwise.
  const userTurn: OpenAI.Chat.ChatCompletionMessageParam = hasImages
    ? {
        role: "user",
        content: [
          { type: "text" as const, text: userMessage },
          ...((images as string[]).map((b64) => ({
            type: "image_url" as const,
            image_url: { url: b64.startsWith("data:") ? b64 : `data:image/png;base64,${b64}` },
          }))),
        ],
      }
    : { role: "user", content: userMessage }

  const messages: OpenAI.Chat.ChatCompletionMessageParam[] = [
    { role: "system", content: systemPrompt },
    ...(history ?? []).map(m => ({ role: m.role as "user" | "assistant", content: m.content })),
    userTurn,
  ]

  const client = getLocalClient()
  // Vision requests need a vision model; default to llava:7b when images are
  // present and no explicit model was passed.
  const activeModel = model || (hasImages ? "llava:7b" : OLLAMA_MODEL)

  // ─── Streaming path (SSE) ─────────────────────────────────────────────
  // Clients pass `stream: true` to receive token deltas as they arrive.
  // The stream ends with a terminal `data: {"done":true,"conversationId":...}`
  // event so the client can dispose of its EventSource cleanly.
  if (wantsStream) {
    const encoder = new TextEncoder()
    const body = new ReadableStream({
      async start(controller) {
        const send = (obj: unknown) => controller.enqueue(encoder.encode(`data: ${JSON.stringify(obj)}\n\n`))
        let full = ""
        try {
          const stream = await client.chat.completions.create({
            model: activeModel,
            messages,
            temperature: 0.7,
            max_tokens: 600,
            stream: true,
          })
          for await (const chunk of stream) {
            const delta = chunk.choices[0]?.delta?.content ?? ""
            if (delta) {
              full += delta
              send({ delta })
            }
          }
          if (activeConversationId && full) {
            await supabase.from("eve_history").insert({
              user_id: USER_ID,
              conversation_id: activeConversationId,
              role: "assistant",
              content: full,
              summarized: false,
            })
            // Auto-summarize into the memory bank when unsummarized count crosses 20
            maybeSummarize(supabase).catch(() => {})
          }
          send({ done: true, conversationId: activeConversationId, model: activeModel, brain: "local" })
        } catch (err: any) {
          send({ error: `Local LLM unreachable: ${err?.message ?? String(err)}` })
        } finally {
          controller.close()
        }
      },
    })
    return new Response(body, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
      },
    })
  }

  // ─── Non-streaming path (single JSON response) ────────────────────────
  try {
    const res = await client.chat.completions.create({
      model: activeModel,
      messages,
      temperature: 0.7,
      max_tokens: 600,
    })

    const content = res.choices[0]?.message?.content ?? ""

    if (activeConversationId && content) {
      await supabase.from("eve_history").insert({
        user_id: USER_ID,
        conversation_id: activeConversationId,
        role: "assistant",
        content,
        summarized: false,
      })
      // Auto-summarize into the memory bank when unsummarized count crosses 20
      maybeSummarize(supabase).catch(() => {})
    }

    return new Response(
      JSON.stringify({ content, conversationId: activeConversationId, model: activeModel, brain: "local" }),
      { headers: { "Content-Type": "application/json" } }
    )
  } catch (err: any) {
    return new Response(
      JSON.stringify({ error: `Local LLM unreachable: ${err?.message ?? String(err)}` }),
      { status: 503, headers: { "Content-Type": "application/json" } }
    )
  }
}
