"use client"

import { useEffect, useRef, useState, useCallback } from "react"
import { useEveVoice } from "@/hooks/useEveVoice"
import EveMessage from "@/components/dashboard/EveMessage"
import { UserAvatar, EveAvatar } from "@/components/ui/UserAvatar"
import MentionInput, { type MentionInputHandle } from "@/components/mentions/MentionInput"
import { renderPlainWithMentions } from "@/components/mentions/MentionRenderer"
import { stripMentionsToPlain } from "@/lib/mentions/parse"
import {
  Mic, MicOff, Send, Plus, Brain, GitCommitHorizontal,
  Volume2, VolumeX, Square, Pencil, Trash2, Tag, ChevronRight, ChevronDown, X,
  Menu, MessageSquare, Search, CalendarDays, GripVertical, Copy, AlertTriangle,
} from "lucide-react"

type Conversation = { id: string; title: string; created_at: string; updated_at: string }
type HistoryRow = { id: string; role: string; content: string; created_at: string }
type Citation = { url: string; title: string; snippet?: string }
type ToolCallTrace = { name: string; args: Record<string, unknown>; result: Record<string, unknown> & { success?: boolean; error?: string } }
type Message = { id: string; role: "user" | "assistant"; content: string; created_at?: string; citations?: Citation[]; toolCalls?: ToolCallTrace[]; brain?: string }
type Memory = { id: string; type: string; content: string; priority: number; source: string; created_at: string }
type Topic = { id: string; conversation_id: string; label: string; description: string; color: string; created_at: string }

const TOPIC_COLORS: Record<string, { border: string; text: string; bg: string; dot: string }> = {
  cyan:    { border: "border-primary/40",    text: "text-primary",    bg: "bg-primary/8",    dot: "bg-primary" },
  amber:   { border: "border-amber-500/40",   text: "text-amber-400",   bg: "bg-amber-500/8",   dot: "bg-amber-400" },
  emerald: { border: "border-emerald-500/40", text: "text-emerald-400", bg: "bg-emerald-500/8", dot: "bg-emerald-400" },
  rose:    { border: "border-rose-500/40",    text: "text-rose-400",    bg: "bg-rose-500/8",    dot: "bg-rose-400" },
  violet:  { border: "border-violet-500/40",  text: "text-violet-400",  bg: "bg-violet-500/8",  dot: "bg-violet-400" },
}

const WELCOME: Message = {
  id: "welcome",
  role: "assistant",
  content: "Eve online. All systems nominal. Memory bank active. What's the move?",
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}
function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })
}
function groupByDate(conversations: Conversation[]) {
  const groups: Record<string, Conversation[]> = {}
  for (const c of conversations) {
    const label = formatDate(c.updated_at)
    if (!groups[label]) groups[label] = []
    groups[label].push(c)
  }
  return groups
}

// Interleave topics as dividers between messages based on created_at ordering
function buildTimeline(messages: Message[], topics: Topic[]): Array<Message | Topic & { _type: "topic" }> {
  const items: Array<(Message & { _type?: undefined }) | (Topic & { _type: "topic" })> = []
  const sortedTopics = [...topics].sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime())
  let ti = 0
  for (const msg of messages) {
    const msgTime = msg.created_at ? new Date(msg.created_at).getTime() : Infinity
    while (ti < sortedTopics.length && new Date(sortedTopics[ti].created_at).getTime() <= msgTime) {
      items.push({ ...sortedTopics[ti], _type: "topic" })
      ti++
    }
    items.push(msg)
  }
  while (ti < sortedTopics.length) {
    items.push({ ...sortedTopics[ti], _type: "topic" })
    ti++
  }
  return items
}

export default function MaxwellClient({
  conversations: initialConversations,
  initialConversationId,
  initialMessages,
  userName,
  userAvatarUrl,
}: {
  conversations: Conversation[]
  initialConversationId: string | null
  initialMessages: HistoryRow[]
  userName: string
  userAvatarUrl: string | null
}) {
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<MentionInputHandle>(null)
  const [input, setInput] = useState("")
  const [isLoading, setIsLoading] = useState(false)

  // ── Multi-select (⌘-click) + edit & regenerate + search ────────────────────
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editingText, setEditingText] = useState("")
  const [chatSearchActive, setChatSearchActive] = useState(false)
  const [chatSearchQuery, setChatSearchQuery] = useState("")
  const [chatSearchIndex, setChatSearchIndex] = useState(0)

  // ── Slash command popup (mirrors Lumen's SlashCommandRegistry + TemplateLibrary)
  // Five built-in templates + six action commands. Renders above the input
  // when the user types `/`. Selecting a template inserts its body; selecting
  // an action runs immediately.
  type SlashEntry = {
    id: string
    detail: string
    kind: "action" | "template"
    body?: string  // for templates
    run?: () => void  // for actions
  }
  const slashRegistry: SlashEntry[] = [
    { id: "/standup", detail: "Template: morning standup brief", kind: "template",
      body: "Give me a brief morning standup: yesterday's wins, today's priorities, blockers, and anything I'm forgetting." },
    { id: "/review", detail: "Template: weekly review", kind: "template",
      body: "Help me run a weekly review. Pull all operations updated this week, agent findings, completed research, and surface what I might have missed." },
    { id: "/dump", detail: "Template: brain-dump capture", kind: "template",
      body: "I'm about to brain-dump. Capture what I say as memories or operations as appropriate. Ask only if something is genuinely ambiguous." },
    { id: "/morning", detail: "Template: morning brief", kind: "template",
      body: "Morning brief: what's overdue, what's important today, status pulse on active operations, anything that needs my attention." },
    { id: "/eod", detail: "Template: end-of-day wrap", kind: "template",
      body: "End-of-day wrap: summarize what I worked on today across operations and conversations, what's still open, and one thing I should sleep on." },
    { id: "/new", detail: "End this thread, start a fresh one", kind: "action",
      run: () => { startNewConversation() } },
    { id: "/clear", detail: "Clear visible messages", kind: "action",
      run: () => setMessages([]) },
    { id: "/help", detail: "Show available slash commands", kind: "action",
      run: () => {
        const help = "**Slash commands**\n\n" +
          "Templates: `/standup`, `/review`, `/dump`, `/morning`, `/eod`\n" +
          "Actions: `/new`, `/clear`, `/help`\n\n" +
          "Type `@` for mentions across operations, agents, records, conversations, directives, memories."
        setMessages(prev => [...prev, {
          id: crypto.randomUUID(),
          role: "assistant",
          content: help,
          created_at: new Date().toISOString(),
        }])
      } },
  ]
  const slashTrimmed = input.trim()
  const slashShowing = slashTrimmed.startsWith("/") && !slashTrimmed.includes(" ")
  const slashMatches = slashShowing
    ? slashRegistry.filter(c => c.id.toLowerCase().startsWith(slashTrimmed.toLowerCase()))
    : []

  // ── Voice ──────────────────────────────────────────────────────────────────
  const submitMessageRef = useRef<(text: string) => void>(() => {})
  const handleVoiceTranscript = useCallback((text: string) => {
    setInput("")
    submitMessageRef.current(text)
  }, [])

  const {
    eveSpeaking, eveMuted, toggleEveMute, stopEve, speakAsEve,
    directorListening, micActive, startMic, stopMic,
    pttStart, pttStop, pttActive,
    voiceSupported, transcript, ttsError,
  } = useEveVoice(handleVoiceTranscript)

  const [voiceEnabled, setVoiceEnabled] = useState(false)
  const voiceEnabledRef = useRef(false)
  voiceEnabledRef.current = voiceEnabled
  const [ttsMode, setTtsMode] = useState<"grok" | "system">("grok")
  const [showMemory, setShowMemory] = useState(false)
  const [memories, setMemories] = useState<Memory[]>([])
  const [memoriesLoading, setMemoriesLoading] = useState(false)
  const [summarizing, setSummarizing] = useState(false)

  const [conversations, setConversations] = useState<Conversation[]>(initialConversations)
  const [activeConversationId, setActiveConversationId] = useState<string | null>(initialConversationId)
  const [loadingMessages, setLoadingMessages] = useState(false)
  const [editingTitleId, setEditingTitleId] = useState<string | null>(null)
  const [editingTitleValue, setEditingTitleValue] = useState("")
  const [expandedConvs, setExpandedConvs] = useState<Set<string>>(new Set(initialConversationId ? [initialConversationId] : []))

  // Mobile: sessions drawer + memory overlay toggles
  const [mobileSessionsOpen, setMobileSessionsOpen] = useState(false)

  // ── Sessions sidebar: search, date filter, resize ──────────────────────
  const [sidebarWidth, setSidebarWidth] = useState(264)
  const [isDesktop, setIsDesktop] = useState(false)
  useEffect(() => {
    const check = () => setIsDesktop(window.innerWidth >= 768)
    check()
    window.addEventListener("resize", check)
    return () => window.removeEventListener("resize", check)
  }, [])
  const isDragging = useRef(false)
  const [collapsedDates, setCollapsedDates] = useState<Set<string>>(new Set())
  const [searchQuery, setSearchQuery] = useState("")
  const [searchResults, setSearchResults] = useState<Map<string, string>>(new Map()) // convId -> matched snippet
  const [isSearching, setIsSearching] = useState(false)
  const [dateFilter, setDateFilter] = useState<"all" | "today" | "week" | "month" | "custom">("all")
  const [showDatePicker, setShowDatePicker] = useState(false)
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const searchDebounce = useRef<NodeJS.Timeout | null>(null)

  const [messages, setMessages] = useState<Message[]>(
    initialMessages.length > 0
      ? initialMessages.map((h) => ({ id: h.id, role: h.role as "user" | "assistant", content: h.content, created_at: h.created_at }))
      : [WELCOME]
  )

  // ── Topics ─────────────────────────────────────────────────────────────────
  const [topics, setTopics] = useState<Topic[]>([])
  const [showAddTopic, setShowAddTopic] = useState(false)
  const [newTopicLabel, setNewTopicLabel] = useState("")
  const [newTopicColor, setNewTopicColor] = useState<string>("cyan")

  async function loadTopics(convId: string) {
    const res = await fetch(`/api/eve/topics?conversationId=${convId}`)
    if (res.ok) {
      const data = await res.json()
      setTopics(data.topics ?? [])
    }
  }

  async function addTopic() {
    if (!newTopicLabel.trim() || !activeConversationId) return
    const res = await fetch("/api/eve/topics", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ conversationId: activeConversationId, label: newTopicLabel.trim(), color: newTopicColor }),
    })
    if (res.ok) {
      const data = await res.json()
      setTopics(prev => [...prev, data.topic])
      setNewTopicLabel("")
      setShowAddTopic(false)
    }
  }

  async function deleteTopic(id: string) {
    await fetch("/api/eve/topics", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    })
    setTopics(prev => prev.filter(t => t.id !== id))
  }

  const lastEveMessage = [...messages].reverse().find(m => m.role === "assistant")

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages, isLoading, topics])

  useEffect(() => {
    if (activeConversationId) {
      localStorage.setItem("nx_active_conv", activeConversationId)
      loadTopics(activeConversationId)
    }
  }, [activeConversationId])

  useEffect(() => { loadMemories() }, [])

  // Accept a prefill handoff from other parts of the dashboard (e.g. the
  // record detail drawer's "Ask Eve about this" button). We use sessionStorage
  // to avoid blowing out the URL for long record content.
  useEffect(() => {
    try {
      const prefill = sessionStorage.getItem("eve_prefill")
      if (prefill) {
        setInput(prefill)
        sessionStorage.removeItem("eve_prefill")
        // Focus the input so the Director can just hit enter
        setTimeout(() => inputRef.current?.focus(), 50)
      }
    } catch { /* ignore storage errors */ }
  }, [])

  async function loadMemories() {
    setMemoriesLoading(true)
    try {
      const res = await fetch("/api/eve/memory")
      if (res.ok) {
        const data = await res.json()
        setMemories(data.memories ?? [])
      }
    } finally {
      setMemoriesLoading(false)
    }
  }

  async function loadConversation(convId: string) {
    if (convId === activeConversationId) return
    setLoadingMessages(true)
    setActiveConversationId(convId)
    setTopics([])
    setExpandedConvs(prev => new Set(prev).add(convId))
    window.history.replaceState(null, "", `/dashboard/maxwell?c=${convId}`)
    try {
      const [histRes, topicRes] = await Promise.all([
        fetch(`/api/eve/history?conversationId=${convId}`),
        fetch(`/api/eve/topics?conversationId=${convId}`),
      ])
      if (histRes.ok) {
        const data = await histRes.json()
        const msgs: Message[] = (data.messages ?? []).map((h: HistoryRow) => ({
          id: h.id, role: h.role as "user" | "assistant", content: h.content, created_at: h.created_at,
        }))
        setMessages(msgs.length > 0 ? msgs : [WELCOME])
      }
      if (topicRes.ok) {
        const data = await topicRes.json()
        setTopics(data.topics ?? [])
      }
    } finally {
      setLoadingMessages(false)
    }
  }

  async function startNewConversation() {
    const res = await fetch("/api/eve/conversations", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: "New Session" }),
    })
    if (!res.ok) return
    const data = await res.json()
    const conv: Conversation = data.conversation
    setConversations(prev => [conv, ...prev])
    setActiveConversationId(conv.id)
    setMessages([WELCOME])
    setTopics([])
    setExpandedConvs(prev => new Set(prev).add(conv.id))
    window.history.replaceState(null, "", `/dashboard/maxwell?c=${conv.id}`)
    setTimeout(() => inputRef.current?.focus(), 100)
  }

  async function handleRenameConversation(id: string, title: string) {
    await fetch("/api/eve/conversations", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, title }),
    })
    setConversations(prev => prev.map(c => c.id === id ? { ...c, title } : c))
    setEditingTitleId(null)
  }

  async function handleDeleteConversation(id: string) {
    if (!confirm("Delete this conversation? This cannot be undone.")) return
    const res = await fetch("/api/eve/conversations", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    })
    if (!res.ok) {
      alert("Couldn't delete that conversation. Try again or refresh.")
      return
    }
    const remaining = conversations.filter(c => c.id !== id)
    setConversations(remaining)
    if (activeConversationId === id) {
      if (remaining.length > 0) await loadConversation(remaining[0].id)
      else { setActiveConversationId(null); setMessages([WELCOME]); setTopics([]) }
    }
  }

  useEffect(() => {
    submitMessageRef.current = submitMessage
  }, [isLoading, activeConversationId, conversations]) // eslint-disable-line react-hooks/exhaustive-deps

  async function submitMessage(text: string) {
    if (!text.trim() || isLoading) return

    let convId = activeConversationId
    if (!convId) {
      const res = await fetch("/api/eve/conversations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: text.slice(0, 60) }),
      })
      if (!res.ok) {
        // Restore the user's text so they don't lose what they typed.
        setInput(text)
        alert("Couldn't start a new conversation. Check your connection and try again.")
        return
      }
      const data = await res.json()
      convId = data.conversation.id
      setConversations(prev => [data.conversation, ...prev])
      setActiveConversationId(convId)
      setExpandedConvs(prev => new Set(prev).add(convId!))
      window.history.replaceState(null, "", `/dashboard/maxwell?c=${convId}`)
    }

    const activeConv = conversations.find(c => c.id === convId)
    if (activeConv?.title === "New Session") handleRenameConversation(convId!, text.slice(0, 60))

    const userMsg: Message = { id: crypto.randomUUID(), role: "user", content: text, created_at: new Date().toISOString() }
    setMessages(prev => [...prev.filter(m => m.id !== "welcome"), userMsg])
    setIsLoading(true)

    try {
      // Streaming path — Eve appears word-by-word, tool cards land as
      // they execute. Single placeholder message that we mutate in place.
      const placeholderId = crypto.randomUUID()
      setMessages(prev => [...prev, {
        id: placeholderId,
        role: "assistant",
        content: "",
        created_at: new Date().toISOString(),
        citations: [],
        toolCalls: [],
        brain: "grok",
      }])

      const res = await fetch("/api/eve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ userMessage: text, conversationId: convId, stream: true }),
      })
      if (!res.ok || !res.body) {
        const errorText = res.body ? "stream missing" : await res.text()
        throw new Error(`API error ${res.status}: ${errorText}`)
      }

      const reader = res.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ""
      let assistantContent = ""
      const collectedToolCalls: ToolCallTrace[] = []

      // SSE parser — events delimited by \n\n, payload is `data: {...}`.
      while (true) {
        const { value, done } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })

        let idx: number
        while ((idx = buffer.indexOf("\n\n")) !== -1) {
          const event = buffer.slice(0, idx).trim()
          buffer = buffer.slice(idx + 2)
          if (!event.startsWith("data:")) continue
          const json = event.slice(5).trim()
          if (!json) continue
          let evt: { type: string; content?: string; name?: string; args?: Record<string, unknown>; result?: Record<string, unknown> & { success?: boolean; error?: string }; conversationId?: string }
          try { evt = JSON.parse(json) } catch { continue }

          if (evt.type === "delta" && evt.content) {
            assistantContent += evt.content
            setMessages(prev => prev.map(m =>
              m.id === placeholderId ? { ...m, content: assistantContent } : m
            ))
          } else if (evt.type === "tool_call" && evt.name) {
            const tc: ToolCallTrace = {
              name: evt.name,
              args: evt.args ?? {},
              result: evt.result ?? {},
            }
            collectedToolCalls.push(tc)
            setMessages(prev => prev.map(m =>
              m.id === placeholderId ? { ...m, toolCalls: [...(m.toolCalls ?? []), tc] } : m
            ))
          } else if (evt.type === "done") {
            if (evt.content) assistantContent = evt.content
          }
        }
      }

      // Final pass — make sure content matches done event exactly
      setMessages(prev => prev.map(m =>
        m.id === placeholderId ? { ...m, content: assistantContent } : m
      ))

      // Always reload topics after Eve responds — she may have called mark_topic
      if (convId) loadTopics(convId)

      if (voiceEnabledRef.current) speakAsEve(stripMentionsToPlain(assistantContent), ttsMode)

      setConversations(prev => {
        const conv = prev.find(c => c.id === convId)
        if (!conv) return prev
        return [{ ...conv, updated_at: new Date().toISOString() }, ...prev.filter(c => c.id !== convId)]
      })
    } catch (err) {
      // Mark errors with a sentinel prefix so the renderer styles them as
      // a subtle dim line, not a full Eve bubble. Drop any empty placeholder
      // assistant message that the streaming path created — it'd render as
      // an empty card otherwise.
      const detail = err instanceof Error ? err.message : "Unknown error"
      setMessages(prev => {
        const cleaned = prev.filter(m => !(m.role === "assistant" && !m.content.trim()))
        return [...cleaned, {
          id: crypto.randomUUID(),
          role: "assistant",
          content: `[error]Something went wrong on my end — ${detail}. Try again.`,
        }]
      })
    } finally {
      setIsLoading(false)
    }
  }

  /// Edit & regenerate: truncate the thread back to the edited user message
  /// and re-submit with the new text. Eve answers fresh against the prior
  /// context. DB rows for dropped turns stay; only the visible thread is
  /// what the user sees.
  function saveEdit(messageId: string) {
    const cleaned = editingText.trim()
    if (!cleaned) { setEditingId(null); return }
    const idx = messages.findIndex(m => m.id === messageId)
    if (idx < 0) { setEditingId(null); return }
    setMessages(prev => prev.slice(0, idx))
    setEditingId(null)
    setEditingText("")
    submitMessage(cleaned)
  }

  /// Multi-select helpers
  const selectedMessages = messages.filter(m => selectedIds.has(m.id))
  function readSelected() {
    const joined = selectedMessages.map(m => stripMentionsToPlain(m.content)).join(". \n\n")
    if (!joined) return
    speakAsEve(joined, ttsMode)
  }
  function copySelected() {
    const joined = selectedMessages.map(m => m.content).join("\n\n")
    if (!joined) return
    navigator.clipboard.writeText(joined)
  }

  /// Search helpers
  const chatSearchMatches = messages
    .map((m, i) => ({ m, i }))
    .filter(({ m }) => chatSearchActive && chatSearchQuery.trim() &&
      m.content.toLowerCase().includes(chatSearchQuery.trim().toLowerCase()))
  function advanceChatSearch(step: number) {
    if (chatSearchMatches.length === 0) return
    setChatSearchIndex((chatSearchIndex + step + chatSearchMatches.length) % chatSearchMatches.length)
  }

  // ⌘F to toggle search
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if ((e.metaKey || e.ctrlKey) && e.key === "f") {
        e.preventDefault()
        setChatSearchActive(v => !v)
        if (chatSearchActive) { setChatSearchQuery(""); setChatSearchIndex(0) }
      } else if (e.key === "Escape" && chatSearchActive) {
        setChatSearchActive(false)
        setChatSearchQuery("")
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [chatSearchActive])

  // Auto-scroll to current search match
  useEffect(() => {
    if (!chatSearchActive || chatSearchMatches.length === 0) return
    const target = chatSearchMatches[Math.min(chatSearchIndex, chatSearchMatches.length - 1)]
    const el = document.querySelector(`[data-message-id="${target.m.id}"]`)
    el?.scrollIntoView({ behavior: "smooth", block: "center" })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chatSearchIndex, chatSearchQuery])

  /// Slash command runner — templates insert their body, actions run.
  function runSlashEntry(entry: SlashEntry) {
    if (entry.kind === "template" && entry.body) {
      setInput(entry.body)
      // Don't clear — let user edit before sending
      return
    }
    if (entry.kind === "action" && entry.run) {
      entry.run()
      setInput("")
      inputRef.current?.clear()
    }
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!input.trim() || isLoading) return
    // Slash command override — Enter on a slash command runs the top match
    if (slashShowing && slashMatches.length > 0) {
      runSlashEntry(slashMatches[0])
      return
    }
    const text = input.trim()
    setInput("")
    inputRef.current?.clear()
    submitMessage(text)
  }

  async function handleManualSummarize() {
    setSummarizing(true)
    try {
      const res = await fetch("/api/eve/summarize", { method: "POST" })
      const data = await res.json()
      await loadMemories()
      setMessages(prev => [...prev, {
        id: crypto.randomUUID(), role: "assistant",
        content: data.skipped
          ? "Memory bank is current. Not enough new messages to summarize yet."
          : `Memory bank updated. ${data.memoriesExtracted} new memory entries committed to long-term storage.`,
      }])
    } finally {
      setSummarizing(false)
    }
  }

  async function handleDeleteMemory(id: string) {
    await fetch("/api/eve/memory", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    })
    setMemories(prev => prev.filter(m => m.id !== id))
  }

  function toggleMic() {
    if (micActive || directorListening) stopMic()
    else startMic()
  }

  const memoryTypeColor = (type: string) => {
    switch (type) {
      case "task":      return "text-red-400 border-red-500/30 bg-red-500/5"
      case "objective": return "text-orange-400 border-orange-500/30 bg-orange-500/5"
      case "project":   return "text-accent border-accent/30 bg-accent/5"
      case "preference":return "text-emerald-400 border-emerald-500/30 bg-emerald-500/5"
      default:          return "text-accent border-accent/30 bg-accent/5"
    }
  }

  // ── Filter conversations by date + search ─────────────────────────────
  const filteredConversations = conversations.filter(c => {
    const d = new Date(c.updated_at)
    const now = new Date()
    if (dateFilter === "today") {
      return d.toDateString() === now.toDateString()
    } else if (dateFilter === "week") {
      const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
      return d >= weekAgo
    } else if (dateFilter === "month") {
      const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)
      return d >= monthAgo
    } else if (dateFilter === "custom" && (dateFrom || dateTo)) {
      if (dateFrom && d < new Date(dateFrom)) return false
      if (dateTo && d > new Date(dateTo + "T23:59:59")) return false
    }
    // If searching, only show conversations that matched
    if (searchQuery.trim() && searchResults.size > 0) {
      return searchResults.has(c.id)
    }
    return true
  })

  const grouped = groupByDate(filteredConversations)

  // ── Search across all conversations ────────────────────────────────────
  useEffect(() => {
    if (searchDebounce.current) clearTimeout(searchDebounce.current)
    const q = searchQuery.trim()
    if (!q || q.length < 2) {
      setSearchResults(new Map())
      setIsSearching(false)
      return
    }
    setIsSearching(true)
    searchDebounce.current = setTimeout(async () => {
      try {
        const res = await fetch(`/api/eve/search?q=${encodeURIComponent(q)}`)
        if (res.ok) {
          const data = await res.json()
          const map = new Map<string, string>()
          for (const r of data.results ?? []) {
            if (!map.has(r.conversation_id)) {
              map.set(r.conversation_id, r.snippet)
            }
          }
          setSearchResults(map)
        }
      } finally {
        setIsSearching(false)
      }
    }, 400)
    return () => { if (searchDebounce.current) clearTimeout(searchDebounce.current) }
  }, [searchQuery])
  const isMicOn = micActive || directorListening || pttActive
  const timeline = buildTimeline(messages, topics)

  // Wrap loadConversation + startNew to also close the mobile drawer
  async function handleLoadConversation(id: string) {
    setMobileSessionsOpen(false)
    return loadConversation(id)
  }
  async function handleStartNewConversation() {
    setMobileSessionsOpen(false)
    return startNewConversation()
  }

  return (
    <div className="flex h-[calc(100dvh-5rem)] md:h-screen overflow-hidden bg-background">

      {/* ── Mobile backdrop for sessions drawer ────────────────────────────── */}
      {mobileSessionsOpen && (
        <button
          className="md:hidden fixed inset-0 bg-foreground/20 backdrop-blur-sm z-30"
          onClick={() => setMobileSessionsOpen(false)}
          aria-label="Close sessions"
        />
      )}

      {/* ── Conversation Sidebar (drawer on mobile, resizable on desktop) ── */}
      <aside
        className={`
          fixed md:static inset-y-0 left-0 w-[85%] max-w-[320px] md:max-w-none
          border-r border-border bg-card flex flex-col flex-shrink-0
          z-40 transition-transform duration-300 ease-out md:transition-none
          ${mobileSessionsOpen ? "translate-x-0" : "-translate-x-full md:translate-x-0"}
          pb-20 md:pb-0 relative
        `}
        style={isDesktop ? { width: sidebarWidth } : undefined}
      >
        {/* Drag handle — right edge */}
        <div
          className="hidden md:block absolute top-0 right-0 w-1.5 h-full cursor-col-resize z-50 group hover:bg-primary/20 active:bg-primary/30 transition-colors"
          onMouseDown={(e) => {
            e.preventDefault()
            isDragging.current = true
            const startX = e.clientX
            const startW = sidebarWidth
            const onMove = (ev: MouseEvent) => {
              if (!isDragging.current) return
              const delta = ev.clientX - startX
              setSidebarWidth(Math.max(200, Math.min(600, startW + delta)))
            }
            const onUp = () => {
              isDragging.current = false
              document.removeEventListener("mousemove", onMove)
              document.removeEventListener("mouseup", onUp)
            }
            document.addEventListener("mousemove", onMove)
            document.addEventListener("mouseup", onUp)
          }}
        >
          <div className="absolute right-0 top-1/2 -translate-y-1/2 w-1 h-8 rounded-full bg-border group-hover:bg-primary/50 transition-colors" />
        </div>

        <div data-sidebar-content className="p-3 border-b border-border">
          <div className="flex items-center justify-between gap-2 mb-2">
            <div className="min-w-0">
              <p className="text-sm font-bold text-foreground">Sessions</p>
              <p className="text-[10px] text-muted-foreground mt-0.5">
                {filteredConversations.length === conversations.length
                  ? `${conversations.length} conversations`
                  : `${filteredConversations.length} of ${conversations.length}`
                }
              </p>
            </div>
            <div className="flex items-center gap-1">
              <button
                onClick={handleStartNewConversation}
                className="flex items-center gap-1.5 text-sm font-bold text-accent border border-accent/50 bg-accent/10 px-3 py-2 rounded-xl hover:bg-accent/20 transition-colors"
                title="New session"
              >
                <Plus size={15} />
                New
              </button>
              <button
                onClick={() => setMobileSessionsOpen(false)}
                className="md:hidden p-2 text-muted-foreground hover:text-foreground rounded-lg"
                aria-label="Close sessions"
              >
                <X size={18} />
              </button>
            </div>
          </div>

          {/* Search bar */}
          <div className="relative mb-2">
            <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground/40" />
            <input
              type="text"
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              placeholder="Search conversations..."
              className="w-full pl-8 pr-8 py-2 text-xs bg-background border border-border rounded-lg text-foreground placeholder:text-muted-foreground/40 focus:outline-none focus:border-primary/40 transition-colors"
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery("")}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-muted-foreground/40 hover:text-foreground"
              >
                <X size={12} />
              </button>
            )}
          </div>

          {/* Date filter pills */}
          <div className="flex items-center gap-1 flex-wrap">
            {(["all", "today", "week", "month"] as const).map(f => (
              <button
                key={f}
                onClick={() => { setDateFilter(f); setShowDatePicker(false) }}
                className={`px-2 py-1 text-[10px] font-medium rounded-md transition-colors capitalize ${
                  dateFilter === f
                    ? "bg-primary/15 text-primary border border-primary/30"
                    : "text-muted-foreground/60 hover:text-foreground hover:bg-muted/30 border border-transparent"
                }`}
              >
                {f === "all" ? "All" : f === "week" ? "7d" : f === "month" ? "30d" : f}
              </button>
            ))}
            <button
              onClick={() => { setDateFilter("custom"); setShowDatePicker(v => !v) }}
              className={`p-1 rounded-md transition-colors ${
                dateFilter === "custom"
                  ? "text-primary bg-primary/15"
                  : "text-muted-foreground/40 hover:text-foreground"
              }`}
              title="Custom date range"
            >
              <CalendarDays size={13} />
            </button>

            {(dateFilter !== "all" || searchQuery) && (
              <button
                onClick={() => { setDateFilter("all"); setSearchQuery(""); setShowDatePicker(false) }}
                className="ml-auto text-[10px] text-muted-foreground/50 hover:text-foreground transition-colors"
              >
                Clear
              </button>
            )}
          </div>

          {/* Custom date range picker */}
          {showDatePicker && dateFilter === "custom" && (
            <div className="flex gap-2 mt-2">
              <input
                type="date"
                value={dateFrom}
                onChange={e => setDateFrom(e.target.value)}
                className="flex-1 px-2 py-1.5 text-[10px] bg-background border border-border rounded-md text-foreground focus:outline-none focus:border-primary/40"
              />
              <span className="self-center text-[10px] text-muted-foreground/40">→</span>
              <input
                type="date"
                value={dateTo}
                onChange={e => setDateTo(e.target.value)}
                className="flex-1 px-2 py-1.5 text-[10px] bg-background border border-border rounded-md text-foreground focus:outline-none focus:border-primary/40"
              />
            </div>
          )}

          {/* Search results indicator */}
          {isSearching && (
            <p className="text-[10px] text-primary/60 mt-2 animate-pulse">Searching...</p>
          )}
          {searchQuery.trim().length >= 2 && !isSearching && searchResults.size > 0 && (
            <p className="text-[10px] text-primary/60 mt-2">{searchResults.size} conversation{searchResults.size !== 1 ? "s" : ""} matched</p>
          )}
          {searchQuery.trim().length >= 2 && !isSearching && searchResults.size === 0 && (
            <p className="text-[10px] text-muted-foreground/40 mt-2">No results</p>
          )}
        </div>

        <div className="flex-1 overflow-y-auto">
          {conversations.length === 0 ? (
            <div className="p-6 text-center">
              <p className="text-xs text-muted-foreground/50">No sessions yet</p>
            </div>
          ) : (
            Object.entries(grouped).map(([date, convs]) => {
              const isDateCollapsed = collapsedDates.has(date)
              return (
              <div key={date}>
                <button
                  onClick={() => setCollapsedDates(prev => { const s = new Set(prev); isDateCollapsed ? s.delete(date) : s.add(date); return s })}
                  className="w-full px-3 py-2 sticky top-0 bg-card z-10 flex items-center gap-2 hover:bg-muted/20 transition-colors text-left"
                >
                  {isDateCollapsed ? <ChevronRight size={10} className="text-muted-foreground/40" /> : <ChevronDown size={10} className="text-muted-foreground/40" />}
                  <p className="text-xs font-medium text-muted-foreground flex-1">{date}</p>
                  <span className="text-[9px] text-muted-foreground/30 tabular-nums">{convs.length}</span>
                </button>
                {!isDateCollapsed && convs.map(conv => {
                  const convTopics = conv.id === activeConversationId ? topics : []
                  const isExpanded = expandedConvs.has(conv.id)
                  const isActive = activeConversationId === conv.id
                  return (
                    <div key={conv.id}>
                      <div className={`group relative ${isActive ? "bg-accent/8 border-l-2 border-l-accent" : "border-l-2 border-l-transparent hover:bg-muted/20"}`}>
                        {editingTitleId === conv.id ? (
                          <form
                            className="px-3 py-2"
                            onSubmit={e => { e.preventDefault(); handleRenameConversation(conv.id, editingTitleValue) }}
                          >
                            <input
                              autoFocus
                              value={editingTitleValue}
                              onChange={e => setEditingTitleValue(e.target.value)}
                              onBlur={() => handleRenameConversation(conv.id, editingTitleValue || conv.title)}
                              className="w-full bg-background border border-accent/40 px-2 py-1 text-sm text-foreground focus:outline-none rounded-md"
                            />
                          </form>
                        ) : (
                          <div className="flex items-center">
                            {convTopics.length > 0 && (
                              <button
                                onClick={e => { e.stopPropagation(); setExpandedConvs(prev => { const s = new Set(prev); isExpanded ? s.delete(conv.id) : s.add(conv.id); return s }) }}
                                className="pl-2 py-3 text-muted-foreground/40 hover:text-muted-foreground transition-colors flex-shrink-0"
                              >
                                {isExpanded ? <ChevronDown size={11} /> : <ChevronRight size={11} />}
                              </button>
                            )}
                            <button onClick={() => handleLoadConversation(conv.id)} className={`flex-1 text-left py-3 pr-12 ${convTopics.length > 0 ? "pl-1" : "pl-3"}`}>
                              <p className={`text-sm leading-snug ${sidebarWidth > 300 ? "" : "truncate"} ${isActive ? "text-foreground font-semibold" : "text-foreground/70"}`}>
                                {conv.title}
                              </p>
                              <p className="text-xs text-foreground/40 mt-0.5">{formatTime(conv.updated_at)}</p>
                              {searchQuery && searchResults.has(conv.id) && (
                                <p className="text-[10px] text-primary/50 mt-1 line-clamp-2 italic">
                                  &ldquo;{searchResults.get(conv.id)}&rdquo;
                                </p>
                              )}
                            </button>
                          </div>
                        )}
                        <div className="absolute right-2 top-1/2 -translate-y-1/2 hidden group-hover:flex items-center gap-1">
                          <button
                            onClick={e => { e.stopPropagation(); setEditingTitleId(conv.id); setEditingTitleValue(conv.title) }}
                            className="p-1.5 text-muted-foreground/40 hover:text-accent transition-colors rounded"
                          >
                            <Pencil size={11} />
                          </button>
                          <button
                            onClick={e => { e.stopPropagation(); handleDeleteConversation(conv.id) }}
                            className="p-1.5 text-muted-foreground/40 hover:text-destructive transition-colors rounded"
                          >
                            <Trash2 size={11} />
                          </button>
                        </div>
                      </div>

                      {/* Topic index — shown when expanded */}
                      {isExpanded && convTopics.length > 0 && (
                        <div className="pl-5 pb-1">
                          {convTopics.map(topic => {
                            const c = TOPIC_COLORS[topic.color] ?? TOPIC_COLORS.cyan
                            return (
                              <div key={topic.id} className="flex items-center gap-2 py-1 px-2 group/topic rounded-lg hover:bg-muted/20">
                                <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${c.dot}`} />
                                <span className={`text-xs flex-1 truncate ${c.text}`}>{topic.label}</span>
                                <button
                                  onClick={() => deleteTopic(topic.id)}
                                  className="opacity-0 group-hover/topic:opacity-100 text-muted-foreground/30 hover:text-destructive transition-all"
                                >
                                  <X size={10} />
                                </button>
                              </div>
                            )
                          })}
                        </div>
                      )}
                    </div>
                  )
                })}
              </div>
            )})
          )}
        </div>
      </aside>

      {/* ── Main Chat Area ─────────────────────────────────────────────────── */}
      <div className="flex-1 flex flex-col overflow-hidden min-w-0 w-full relative">

        {/* Search bar (⌘F) */}
        {chatSearchActive && (
          <div className="flex items-center gap-2 px-4 py-2 bg-card/95 backdrop-blur-sm border-b border-border">
            <span className="text-xs font-mono tracking-wider text-muted-foreground">SEARCH</span>
            <input
              autoFocus
              type="text"
              value={chatSearchQuery}
              onChange={(e) => { setChatSearchQuery(e.target.value); setChatSearchIndex(0) }}
              placeholder="Filter this thread…"
              className="flex-1 bg-transparent text-sm outline-none text-foreground placeholder:text-muted-foreground/60"
              onKeyDown={(e) => {
                if (e.key === "Enter") advanceChatSearch(e.shiftKey ? -1 : 1)
                else if (e.key === "Escape") { setChatSearchActive(false); setChatSearchQuery("") }
              }}
            />
            {chatSearchQuery && (
              <span className="text-[10px] font-mono text-muted-foreground">
                {chatSearchMatches.length === 0 ? "no matches" : `${Math.min(chatSearchIndex + 1, chatSearchMatches.length)} of ${chatSearchMatches.length}`}
              </span>
            )}
            <button
              disabled={chatSearchMatches.length === 0}
              onClick={() => advanceChatSearch(-1)}
              className="text-xs px-2 py-0.5 rounded bg-muted/40 hover:bg-muted/60 disabled:opacity-40"
            >▲</button>
            <button
              disabled={chatSearchMatches.length === 0}
              onClick={() => advanceChatSearch(1)}
              className="text-xs px-2 py-0.5 rounded bg-muted/40 hover:bg-muted/60 disabled:opacity-40"
            >▼</button>
            <button
              onClick={() => { setChatSearchActive(false); setChatSearchQuery("") }}
              className="text-xs text-muted-foreground hover:text-foreground"
            >✕</button>
          </div>
        )}

        {/* Multi-select floating action bar */}
        {selectedIds.size > 0 && (
          <div className="absolute bottom-24 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 px-3 py-2 rounded-full bg-card/95 backdrop-blur border border-accent/40 shadow-lg shadow-black/30">
            <span className="text-xs font-medium text-accent">
              {selectedIds.size} SELECTED
            </span>
            <span className="w-px h-4 bg-border" />
            <button
              onClick={readSelected}
              className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-accent text-accent-foreground text-xs font-medium hover:opacity-90"
            >
              <Volume2 size={11} /> READ ALOUD
            </button>
            <button
              onClick={copySelected}
              className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-muted/40 hover:bg-muted/60 text-foreground text-xs font-medium"
            >
              <Copy size={11} /> COPY
            </button>
            <button
              onClick={() => stopEve()}
              className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-muted/30 hover:bg-muted/50 text-foreground/80 text-xs font-medium"
            >
              STOP
            </button>
            <button
              onClick={() => setSelectedIds(new Set())}
              className="text-muted-foreground hover:text-foreground"
              title="Clear selection"
            >
              <X size={14} />
            </button>
          </div>
        )}

        {/* Header */}
        <div className="flex items-center justify-between gap-1.5 px-2 md:px-5 py-2 md:py-3 border-b border-border flex-shrink-0 bg-background/80 backdrop-blur-sm">
          {/* Left: Hamburger (mobile) + Eve status */}
          <div className="flex items-center gap-2 md:gap-3 min-w-0">
            {/* Mobile hamburger / sessions toggle */}
            <button
              onClick={() => setMobileSessionsOpen(true)}
              className="md:hidden p-2 -ml-1 text-muted-foreground hover:text-foreground rounded-lg"
              aria-label="Open sessions"
            >
              <Menu size={20} />
            </button>

            <div className="relative flex items-center justify-center w-9 h-9 flex-shrink-0">
              {/* Animated ring when speaking */}
              {eveSpeaking && (
                <span className="absolute inset-0 rounded-full border-2 border-primary animate-ping opacity-60" />
              )}
              <div className={`w-9 h-9 rounded-full flex items-center justify-center border-2 transition-all duration-300 ${
                eveSpeaking
                  ? "border-primary bg-primary/10 text-primary"
                  : isLoading
                  ? "border-amber-400/60 bg-amber-400/10 text-amber-400"
                  : "border-emerald-500/60 bg-emerald-500/10 text-emerald-400"
              }`}>
                <Volume2 size={15} />
              </div>
            </div>
            <div className="min-w-0">
              <h1 className="text-sm font-bold text-foreground leading-none truncate">Eve</h1>
              <p className="text-xs text-muted-foreground mt-0.5 leading-none">
                {isLoading ? "Processing..." : eveSpeaking ? "Speaking..." : "Ready"}
              </p>
            </div>
          </div>

          {/* Right: controls — compact on mobile, full on desktop */}
          <div className="flex items-center gap-1.5 md:gap-2 flex-shrink-0">
            {summarizing && (
              <span className="hidden md:inline text-xs text-amber-400 animate-pulse font-medium px-2">Committing...</span>
            )}

            {/* Voice toggle */}
            <button
              onClick={() => {
                const next = !voiceEnabled
                voiceEnabledRef.current = next
                setVoiceEnabled(next)
                if (!next) stopEve()
              }}
              title={voiceEnabled ? "Voice on — click to mute Eve" : "Voice off — click to unmute Eve"}
              className={`relative flex items-center gap-2 px-2 md:px-4 py-1.5 md:py-2 rounded-xl border text-sm font-semibold transition-all duration-200 ${
                voiceEnabled
                  ? "bg-primary/15 border-primary/60 text-primary "
                  : "bg-card border-border text-muted-foreground hover:text-foreground hover:border-foreground/30"
              }`}
            >
              {voiceEnabled ? <Volume2 size={16} /> : <VolumeX size={16} />}
              <span className="hidden md:inline">{voiceEnabled ? "Voice" : "Muted"}</span>
            </button>

            {/* Stop speaking */}
            {eveSpeaking && (
              <button
                onClick={stopEve}
                title="Stop Eve speaking"
                className="flex items-center gap-2 px-2 md:px-4 py-1.5 md:py-2 rounded-xl border border-red-500/60 bg-red-500/10 text-red-400 text-sm font-semibold hover:bg-red-500/20 transition-all duration-200 animate-pulse"
              >
                <Square size={14} fill="currentColor" />
                <span className="hidden md:inline">Stop</span>
              </button>
            )}

            {/* Replay last message — desktop only */}
            {lastEveMessage && !eveSpeaking && voiceEnabled && (
              <button
                onClick={() => speakAsEve(stripMentionsToPlain(lastEveMessage.content), ttsMode)}
                title="Replay last Eve message"
                className="hidden md:flex items-center gap-2 px-3 py-2 rounded-xl border border-primary/30 bg-primary/5 text-primary/70 text-sm font-semibold hover:bg-primary/15 hover:text-primary hover:border-primary/60 transition-all duration-200"
              >
                <Volume2 size={15} />
              </button>
            )}

            {/* Memory */}
            <button
              onClick={() => { setShowMemory(!showMemory); if (!showMemory) loadMemories() }}
              title="Memory bank"
              className={`flex items-center gap-2 px-2 md:px-4 py-1.5 md:py-2 rounded-xl border text-sm font-semibold transition-all duration-200 ${
                showMemory
                  ? "bg-violet-500/15 border-violet-500/50 text-violet-400"
                  : "bg-card border-border text-muted-foreground hover:text-foreground hover:border-foreground/30"
              }`}
            >
              <Brain size={16} />
              <span className="hidden md:inline">Memory</span>
              {memories.length > 0 && (
                <span className={`text-xs px-1.5 py-0.5 rounded-full font-bold ${showMemory ? "bg-violet-500/30 text-violet-300" : "bg-muted text-muted-foreground"}`}>
                  {memories.length}
                </span>
              )}
            </button>

            {/* Commit — desktop only, hidden on mobile to save space */}
            <button
              onClick={handleManualSummarize}
              disabled={summarizing || isLoading}
              title="Commit conversation to memory"
              className="hidden md:flex items-center gap-2 px-4 py-2 rounded-xl border border-border bg-card text-muted-foreground text-sm font-semibold hover:text-foreground hover:border-foreground/30 disabled:opacity-30 transition-all duration-200"
            >
              <GitCommitHorizontal size={16} />
              <span>Commit</span>
            </button>
          </div>
        </div>

        <div className="flex flex-1 overflow-hidden">
          {/* Messages */}
          <div className="flex-1 flex flex-col overflow-hidden min-w-0">
            <div className="flex-1 overflow-y-auto px-2 md:px-6 py-3 md:py-6">
              {loadingMessages ? (
                <div className="flex items-center justify-center h-40">
                  <div className="w-6 h-6 border-2 border-accent border-t-transparent rounded-full animate-spin" />
                </div>
              ) : (
                <div className="flex flex-col gap-3 md:gap-5 max-w-3xl mx-auto">
                  {timeline.map((item) => {
                    // Topic divider
                    if ("_type" in item && item._type === "topic") {
                      const t = item as Topic & { _type: "topic" }
                      const c = TOPIC_COLORS[t.color] ?? TOPIC_COLORS.cyan
                      return (
                        <div key={`topic-${t.id}`} className={`flex items-center gap-3 py-2 px-4 rounded-xl border ${c.border} ${c.bg} group/tdiv`}>
                          <Tag size={12} className={c.text} />
                          <div className="flex-1">
                            <span className={`text-xs font-semibold ${c.text}`}>{t.label}</span>
                            {t.description && (
                              <p className="text-xs text-muted-foreground mt-0.5">{t.description}</p>
                            )}
                          </div>
                          <button
                            onClick={() => deleteTopic(t.id)}
                            className="opacity-0 group-hover/tdiv:opacity-100 text-muted-foreground/30 hover:text-destructive transition-all"
                          >
                            <X size={12} />
                          </button>
                        </div>
                      )
                    }

                    // Message
                    const m = item as Message
                    const isUser = m.role === "user"
                    const isSelected = selectedIds.has(m.id)
                    const matchHit = chatSearchActive && chatSearchQuery.trim() &&
                      m.content.toLowerCase().includes(chatSearchQuery.trim().toLowerCase())
                    const isEditing = editingId === m.id

                    // Drop empty assistant placeholders (failed streams). A
                    // bubble with no text + no tool calls is just visual noise.
                    if (!isUser && !m.content.trim() && (!m.toolCalls || m.toolCalls.length === 0)) {
                      return null
                    }

                    // System error sentinel — render as a dim, italic single line
                    // instead of the full Eve message UI.
                    if (!isUser && m.content.startsWith("[error]")) {
                      return (
                        <div key={m.id} className="flex items-start gap-2 text-xs text-muted-foreground/70 italic px-1 py-1">
                          <AlertTriangle size={12} className="text-amber-400/70 mt-0.5 flex-shrink-0" />
                          <span>{m.content.slice("[error]".length)}</span>
                        </div>
                      )
                    }

                    return (
                      <div
                        key={m.id}
                        data-message-id={m.id}
                        className={`flex flex-col gap-1.5 group/msg ${isUser ? "items-end" : "items-start"}
                          ${isSelected ? "ring-2 ring-accent/50 rounded-2xl px-1 -mx-1" : ""}
                          ${matchHit ? "bg-amber-400/5 rounded-2xl px-1 -mx-1" : ""}`}
                        onClick={(e) => {
                          if (e.metaKey || e.ctrlKey) {
                            e.stopPropagation()
                            setSelectedIds(prev => {
                              const next = new Set(prev)
                              if (next.has(m.id)) next.delete(m.id)
                              else next.add(m.id)
                              return next
                            })
                          }
                        }}
                      >
                        <div className="flex items-center gap-2">
                          {isUser ? (
                            <UserAvatar name={userName} src={userAvatarUrl} size="xs" ring="none" />
                          ) : (
                            <EveAvatar size="xs" />
                          )}
                          <span className={`text-sm font-medium ${isUser ? "text-foreground" : "text-foreground/80"}`}>
                            {isUser ? userName : "Eve"}
                          </span>
                          {m.created_at && (
                            <span className="text-xs text-foreground/40">{formatTime(m.created_at)}</span>
                          )}
                          {isUser && !isEditing && (
                            <button
                              onClick={(e) => {
                                e.stopPropagation()
                                setEditingId(m.id)
                                setEditingText(m.content)
                              }}
                              className="opacity-0 group-hover/msg:opacity-100 text-xs text-muted-foreground hover:text-accent font-mono tracking-wider transition-opacity"
                              title="Edit and regenerate Eve's reply"
                            >
                              EDIT
                            </button>
                          )}
                        </div>
                        <div className={isUser
                          ? "rounded-2xl px-3.5 md:px-5 py-2.5 md:py-3.5 bg-primary/12 border border-primary/20 max-w-[92%] md:max-w-[75%]"
                          : "w-full"}
                        >
                          {isUser ? (
                            isEditing ? (
                              <div className="flex flex-col gap-2">
                                <textarea
                                  value={editingText}
                                  onChange={(e) => setEditingText(e.target.value)}
                                  className="bg-transparent border border-accent/40 rounded-lg p-2 text-sm text-foreground w-full resize-none focus:outline-none focus:border-accent"
                                  rows={Math.min(8, Math.max(2, editingText.split("\n").length))}
                                  autoFocus
                                  onKeyDown={(e) => {
                                    if (e.key === "Enter" && !e.shiftKey) {
                                      e.preventDefault()
                                      saveEdit(m.id)
                                    } else if (e.key === "Escape") {
                                      setEditingId(null)
                                    }
                                  }}
                                />
                                <div className="flex gap-2 justify-end text-xs">
                                  <button
                                    onClick={() => setEditingId(null)}
                                    className="text-muted-foreground hover:text-foreground font-mono tracking-wider"
                                  >
                                    CANCEL
                                  </button>
                                  <button
                                    onClick={() => saveEdit(m.id)}
                                    className="text-accent font-mono tracking-wider font-bold"
                                  >
                                    SAVE & REGENERATE
                                  </button>
                                </div>
                              </div>
                            ) : (
                              <p className="text-sm text-foreground leading-relaxed whitespace-pre-wrap break-words">{renderPlainWithMentions(m.content)}</p>
                            )
                          ) : (
                            <EveMessage content={m.content} citations={m.citations ?? []} toolCalls={m.toolCalls ?? []} brain={m.brain} />
                          )}
                        </div>
                      </div>
                    )
                  })}

                  {isLoading && (
                    <div className="flex flex-col gap-1.5 items-start">
                      <span className="text-xs font-semibold text-foreground/60">Eve</span>
                      <div className="bg-card border border-border rounded-2xl px-5 py-4">
                        <div className="flex gap-1.5 items-center h-5">
                          <span className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce" style={{ animationDelay: "0ms" }} />
                          <span className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce" style={{ animationDelay: "150ms" }} />
                          <span className="w-2 h-2 bg-muted-foreground/40 rounded-full animate-bounce" style={{ animationDelay: "300ms" }} />
                        </div>
                      </div>
                    </div>
                  )}
                  <div ref={messagesEndRef} />
                </div>
              )}
            </div>

            {/* ── Input bar ──────────────────────────────────────────────────── */}
            <div className="px-2 md:px-6 pb-2 md:pb-6 pt-1 flex-shrink-0">
              <div className="max-w-3xl mx-auto">
                {/* Transcript pill */}
                {transcript && (
                  <div className="mb-2 flex items-center gap-2 bg-accent/10 border border-accent/20 rounded-xl px-4 py-2">
                    <div className="w-1.5 h-1.5 bg-accent rounded-full animate-pulse flex-shrink-0" />
                    <p className="text-sm text-accent italic flex-1 truncate">{transcript}</p>
                  </div>
                )}

                {/* Add topic inline form */}
                {showAddTopic && (
                  <div className="mb-2 flex items-center gap-2 bg-card border border-border rounded-xl px-3 py-2">
                    <Tag size={13} className="text-muted-foreground flex-shrink-0" />
                    <input
                      autoFocus
                      value={newTopicLabel}
                      onChange={e => setNewTopicLabel(e.target.value)}
                      onKeyDown={e => { if (e.key === "Enter") addTopic(); if (e.key === "Escape") setShowAddTopic(false) }}
                      placeholder="Topic name..."
                      className="flex-1 bg-transparent text-sm text-foreground placeholder:text-muted-foreground focus:outline-none"
                    />
                    <div className="flex gap-1">
                      {Object.keys(TOPIC_COLORS).map(color => (
                        <button
                          key={color}
                          onClick={() => setNewTopicColor(color)}
                          className={`w-4 h-4 rounded-full transition-transform ${TOPIC_COLORS[color].dot} ${newTopicColor === color ? "scale-125 ring-2 ring-foreground/30" : "opacity-50 hover:opacity-100"}`}
                        />
                      ))}
                    </div>
                    <button onClick={addTopic} className="text-xs text-accent font-semibold px-2 py-1 hover:bg-accent/10 rounded-lg transition-colors">Add</button>
                    <button onClick={() => setShowAddTopic(false)} className="text-muted-foreground hover:text-foreground transition-colors"><X size={13} /></button>
                  </div>
                )}

                {/* Slash command popup — sits above the input bar when typing /… */}
                {slashShowing && slashMatches.length > 0 && (
                  <div className="mb-2 rounded-xl border border-border bg-card/95 backdrop-blur shadow-lg shadow-black/30 overflow-hidden max-w-md">
                    <div className="px-3 py-1.5 border-b border-border flex items-center gap-2">
                      <span className="text-[8px] font-mono font-bold tracking-[0.2em] text-violet-400">COMMAND</span>
                      <span className="ml-auto text-[8px] font-mono text-muted-foreground">Enter to run · Esc to clear</span>
                    </div>
                    {slashMatches.map((c) => (
                      <button
                        key={c.id}
                        onClick={() => runSlashEntry(c)}
                        className="w-full flex items-center gap-3 px-3 py-2 hover:bg-muted/40 text-left transition-colors"
                      >
                        <span className="text-[12px] font-mono font-semibold text-violet-400 min-w-[64px]">{c.id}</span>
                        <span className="text-[11px] text-foreground/80 truncate flex-1">{c.detail}</span>
                        <span className="text-xs text-muted-foreground/70">
                          {c.kind === "template" ? "TEMPLATE" : "ACTION"}
                        </span>
                      </button>
                    ))}
                  </div>
                )}

                <div className="flex items-end gap-1.5 md:gap-3 bg-card border border-border rounded-2xl px-2.5 md:px-4 py-2 md:py-3 focus-within:border-accent/50 focus-within:ring-2 focus-within:ring-accent/20 transition-all">
                  <MentionInput
                    ref={inputRef}
                    value={input}
                    onChange={setInput}
                    onSubmit={() => {
                      if (!input.trim() || isLoading) return
                      // Slash override
                      if (slashShowing && slashMatches.length > 0) {
                        runSlashEntry(slashMatches[0])
                        return
                      }
                      const text = input.trim()
                      setInput("")
                      inputRef.current?.clear()
                      submitMessage(text)
                    }}
                    placeholder="Message Eve… (@ to mention operations, records, agents)"
                    disabled={isLoading}
                    unstyled
                    minHeightClass="min-h-[28px]"
                    maxHeightClass="max-h-[96px]"
                    expandable
                    expandedMaxHeightClass="max-h-[55vh]"
                    className="flex-1 pr-8"
                  />

                  <div className="flex items-center gap-1.5 md:gap-2 flex-shrink-0 pb-0.5">
                    {/* Tag topic button */}
                    {activeConversationId && (
                      <button
                        type="button"
                        onClick={() => setShowAddTopic(!showAddTopic)}
                        className={`w-11 h-11 md:w-10 md:h-10 rounded-xl flex items-center justify-center transition-all ${showAddTopic ? "bg-accent/20 text-accent" : "text-muted-foreground hover:text-foreground hover:bg-muted"}`}
                        title="Mark topic in conversation"
                      >
                        <Tag size={18} />
                      </button>
                    )}

                    {/* Mic button */}
                    {voiceSupported && (
                      <button
                        type="button"
                        onMouseDown={e => e.preventDefault()}
                        onClick={toggleMic}
                        className={`w-11 h-11 md:w-10 md:h-10 rounded-xl flex items-center justify-center transition-all ${isMicOn
                          ? "bg-accent text-accent-foreground shadow-lg shadow-accent/30 scale-105"
                          : "text-muted-foreground hover:text-foreground hover:bg-muted"}`}
                        title={isMicOn ? "Stop listening" : "Start voice input"}
                      >
                        {isMicOn ? <MicOff size={18} /> : <Mic size={18} />}
                      </button>
                    )}

                    {/* Send button */}
                    <button
                      type="button"
                      onClick={handleSubmit}
                      disabled={isLoading || !input.trim()}
                      className="w-11 h-11 md:w-10 md:h-10 rounded-xl bg-accent text-accent-foreground flex items-center justify-center hover:bg-accent/90 transition-all disabled:opacity-30 disabled:cursor-not-allowed shadow-lg shadow-accent/20"
                      title="Send message"
                    >
                      <Send size={17} />
                    </button>
                  </div>
                </div>

                <p className="hidden md:block text-xs text-muted-foreground text-center mt-3">
                  Enter to send · Shift+Enter for new line · Type @ to mention{voiceSupported ? " · Tap mic to speak" : ""}
                </p>
              </div>
            </div>
          </div>

          {/* ── Memory Panel — side panel desktop, full overlay on mobile ──── */}
          {showMemory && (
            <>
              {/* Mobile backdrop */}
              <button
                className="md:hidden fixed inset-0 bg-foreground/20 backdrop-blur-sm z-30"
                onClick={() => setShowMemory(false)}
                aria-label="Close memory"
              />
              <div className="fixed md:static inset-y-0 right-0 w-[85%] max-w-sm md:w-72 md:max-w-none md:inset-auto border-l border-border bg-card flex flex-col flex-shrink-0 overflow-hidden z-40 pb-20 md:pb-0">
              <div className="p-4 border-b border-border flex items-center justify-between">
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-foreground">Memory Bank</p>
                  <p className="text-xs text-muted-foreground mt-0.5">{memories.length} entries</p>
                </div>
                <button
                  onClick={() => setShowMemory(false)}
                  className="md:hidden p-1.5 text-muted-foreground hover:text-foreground rounded-lg"
                  aria-label="Close memory"
                >
                  <X size={18} />
                </button>
              </div>
              <div className="flex-1 overflow-y-auto p-3 flex flex-col gap-2">
                {memoriesLoading ? (
                  <div className="flex items-center justify-center h-24">
                    <div className="w-5 h-5 border-2 border-accent border-t-transparent rounded-full animate-spin" />
                  </div>
                ) : memories.length === 0 ? (
                  <div className="p-6 text-center">
                    <p className="text-sm text-muted-foreground leading-relaxed">No memories yet. Use Commit after a conversation.</p>
                  </div>
                ) : (
                  memories.map(mem => (
                    <div key={mem.id} className={`border rounded-xl p-3 relative group ${memoryTypeColor(mem.type)}`}>
                      <div className="flex items-center justify-between mb-2">
                        <span className={`text-xs font-semibold ${memoryTypeColor(mem.type).split(" ")[0]}`}>
                          {mem.type}
                        </span>
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-muted-foreground">P{mem.priority}</span>
                          <button
                            onClick={() => handleDeleteMemory(mem.id)}
                            className="text-muted-foreground/30 hover:text-destructive opacity-0 group-hover:opacity-100 transition-all"
                          >
                            <Trash2 size={11} />
                          </button>
                        </div>
                      </div>
                      <p className="text-sm text-foreground leading-relaxed">{mem.content}</p>
                    </div>
                  ))
                )}
              </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}
