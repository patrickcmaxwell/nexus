"use client"

import { useMemo, useState } from "react"
import {
  Plus, Search, FileText, Database, Flag, AlertTriangle,
  Star, Filter, ChevronDown,
  Circle, PlayCircle, CheckCircle2, CircleSlash, X,
} from "lucide-react"

type RecordType = "note" | "intel" | "data" | "finding" | "alert" | "file"
type RecordStatus = "open" | "doing" | "done" | "blocked" | null

export interface ListRecord {
  id: string
  type: RecordType
  title: string
  content: string
  source: string
  priority: string
  status: RecordStatus
  pinned: boolean
  created_at: string
  parent_record_id: string | null
}

const RECORD_ICONS: Record<RecordType, typeof FileText> = {
  note:    FileText,
  intel:   Search,
  data:    Database,
  finding: Flag,
  alert:   AlertTriangle,
  file:    FileText,
}

const RECORD_COLORS: Record<RecordType, string> = {
  note:    "text-muted-foreground",
  intel:   "text-accent",
  data:    "text-blue-400",
  finding: "text-yellow-400",
  alert:   "text-destructive",
  file:    "text-muted-foreground",
}

const STATUS_ICONS: Record<Exclude<RecordStatus, null>, { icon: typeof Circle; className: string }> = {
  open:    { icon: Circle,       className: "text-muted-foreground" },
  doing:   { icon: PlayCircle,   className: "text-accent" },
  done:    { icon: CheckCircle2, className: "text-green-400" },
  blocked: { icon: CircleSlash,  className: "text-destructive" },
}

const TYPES: RecordType[] = ["note", "intel", "data", "finding", "alert", "file"]
const STATUS_FILTERS = ["open", "doing", "done", "blocked", "none"] as const

type SortKey = "updated" | "created" | "priority" | "status" | "title"

function timeAgo(date: string) {
  const diff = Date.now() - new Date(date).getTime()
  const m = Math.floor(diff / 60000)
  if (m < 1) return "just now"
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

const PRIORITY_RANK: Record<string, number> = { critical: 0, high: 1, normal: 2, low: 3 }
const STATUS_RANK: Record<string, number> = { blocked: 0, doing: 1, open: 2, done: 3, none: 4 }

interface Props {
  records: ListRecord[]
  onOpen: (id: string) => void
  onAdd: () => void
}

export default function RecordsList({ records, onOpen, onAdd }: Props) {
  const [query, setQuery] = useState("")
  const [typeFilters, setTypeFilters] = useState<Set<RecordType>>(new Set())
  const [statusFilter, setStatusFilter] = useState<string | null>(null)
  const [sourceFilter, setSourceFilter] = useState<string | null>(null)
  const [sort, setSort] = useState<SortKey>("created")
  const [filtersOpen, setFiltersOpen] = useState(false)

  // Only top-level records — child (research) records live inside their parent's detail view
  const topLevel = useMemo(() => records.filter(r => r.parent_record_id === null), [records])

  const uniqueSources = useMemo(() => {
    const set = new Set<string>()
    for (const r of topLevel) if (r.source) set.add(r.source)
    return Array.from(set).sort()
  }, [topLevel])

  const filtered = useMemo(() => {
    let list = topLevel

    if (query.trim()) {
      const q = query.toLowerCase()
      list = list.filter(r =>
        r.title.toLowerCase().includes(q) || (r.content ?? "").toLowerCase().includes(q)
      )
    }

    if (typeFilters.size > 0) {
      list = list.filter(r => typeFilters.has(r.type))
    }

    if (statusFilter) {
      if (statusFilter === "none") list = list.filter(r => !r.status)
      else list = list.filter(r => r.status === statusFilter)
    }

    if (sourceFilter) {
      list = list.filter(r => r.source === sourceFilter)
    }

    const sorted = [...list].sort((a, b) => {
      // Pinned always first
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1

      switch (sort) {
        case "priority":
          return (PRIORITY_RANK[a.priority] ?? 99) - (PRIORITY_RANK[b.priority] ?? 99)
        case "status":
          return (STATUS_RANK[a.status ?? "none"] ?? 99) - (STATUS_RANK[b.status ?? "none"] ?? 99)
        case "title":
          return a.title.localeCompare(b.title)
        case "created":
        case "updated":
        default:
          return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      }
    })

    return sorted
  }, [topLevel, query, typeFilters, statusFilter, sourceFilter, sort])

  function toggleType(t: RecordType) {
    setTypeFilters(prev => {
      const next = new Set(prev)
      if (next.has(t)) next.delete(t); else next.add(t)
      return next
    })
  }

  function clearFilters() {
    setQuery("")
    setTypeFilters(new Set())
    setStatusFilter(null)
    setSourceFilter(null)
  }

  const anyFilterActive = query.trim() || typeFilters.size > 0 || statusFilter || sourceFilter

  return (
    <div className="flex flex-col h-full min-h-0">
      {/* Header: count + add */}
      <div className="flex items-center justify-between mb-2 shrink-0">
        <p className="text-[10px] font-mono text-muted-foreground uppercase tracking-widest">
          Records ({filtered.length}{filtered.length !== topLevel.length ? ` / ${topLevel.length}` : ""})
        </p>
        <button
          onClick={onAdd}
          className="text-[10px] font-mono border border-border text-muted-foreground hover:text-accent hover:border-accent/40 px-2 py-0.5 rounded transition-colors flex items-center gap-1"
        >
          <Plus size={10} /> Add
        </button>
      </div>

      {/* Search */}
      <div className="relative mb-2 shrink-0">
        <Search size={11} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <input
          type="search"
          value={query}
          onChange={e => setQuery(e.target.value)}
          placeholder="Search records…"
          className="w-full bg-background border border-border rounded pl-7 pr-2 py-1.5 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50"
        />
      </div>

      {/* Filters + sort row */}
      <div className="flex items-center gap-1 mb-2 shrink-0">
        <button
          onClick={() => setFiltersOpen(v => !v)}
          className={`flex items-center gap-1 text-[10px] font-mono border px-2 py-1 rounded transition-colors ${
            anyFilterActive
              ? "border-accent/40 text-accent bg-accent/5"
              : "border-border text-muted-foreground hover:text-foreground"
          }`}
        >
          <Filter size={10} />
          Filter
          {typeFilters.size + (statusFilter ? 1 : 0) + (sourceFilter ? 1 : 0) > 0 && (
            <span className="bg-accent text-accent-foreground rounded-full text-[9px] font-semibold w-3.5 h-3.5 flex items-center justify-center">
              {typeFilters.size + (statusFilter ? 1 : 0) + (sourceFilter ? 1 : 0)}
            </span>
          )}
        </button>

        <div className="relative ml-auto">
          <select
            value={sort}
            onChange={e => setSort(e.target.value as SortKey)}
            className="appearance-none text-[10px] font-mono bg-background border border-border rounded pl-2 pr-6 py-1 text-muted-foreground focus:outline-none focus:border-accent/50 cursor-pointer"
          >
            <option value="created">Newest first</option>
            <option value="priority">Priority</option>
            <option value="status">Status</option>
            <option value="title">Title A→Z</option>
          </select>
          <ChevronDown size={10} className="absolute right-1.5 top-1/2 -translate-y-1/2 text-muted-foreground pointer-events-none" />
        </div>

        {anyFilterActive && (
          <button
            onClick={clearFilters}
            className="text-[10px] font-mono text-muted-foreground hover:text-destructive flex items-center gap-0.5"
            title="Clear filters"
          >
            <X size={10} />
          </button>
        )}
      </div>

      {/* Filters panel */}
      {filtersOpen && (
        <div className="mb-2 border border-border rounded-lg p-2.5 bg-background space-y-2 shrink-0">
          <div>
            <p className="text-[9px] font-mono text-muted-foreground uppercase tracking-widest mb-1">Type</p>
            <div className="flex flex-wrap gap-1">
              {TYPES.map(t => {
                const active = typeFilters.has(t)
                const Icon = RECORD_ICONS[t]
                return (
                  <button
                    key={t}
                    onClick={() => toggleType(t)}
                    className={`flex items-center gap-1 text-[10px] font-mono px-1.5 py-0.5 rounded border transition-colors ${
                      active
                        ? "border-accent/40 bg-accent/5 text-accent"
                        : "border-border text-muted-foreground hover:text-foreground"
                    }`}
                  >
                    <Icon size={9} />
                    {t}
                  </button>
                )
              })}
            </div>
          </div>
          <div>
            <p className="text-[9px] font-mono text-muted-foreground uppercase tracking-widest mb-1">Status</p>
            <div className="flex flex-wrap gap-1">
              {STATUS_FILTERS.map(s => {
                const active = statusFilter === s
                return (
                  <button
                    key={s}
                    onClick={() => setStatusFilter(active ? null : s)}
                    className={`text-[10px] font-mono px-1.5 py-0.5 rounded border transition-colors ${
                      active
                        ? "border-accent/40 bg-accent/5 text-accent"
                        : "border-border text-muted-foreground hover:text-foreground"
                    }`}
                  >
                    {s}
                  </button>
                )
              })}
            </div>
          </div>
          {uniqueSources.length > 1 && (
            <div>
              <p className="text-[9px] font-mono text-muted-foreground uppercase tracking-widest mb-1">Source</p>
              <div className="flex flex-wrap gap-1">
                {uniqueSources.map(s => {
                  const active = sourceFilter === s
                  return (
                    <button
                      key={s}
                      onClick={() => setSourceFilter(active ? null : s)}
                      className={`text-[10px] font-mono px-1.5 py-0.5 rounded border transition-colors truncate max-w-[120px] ${
                        active
                          ? "border-accent/40 bg-accent/5 text-accent"
                          : "border-border text-muted-foreground hover:text-foreground"
                      }`}
                      title={s}
                    >
                      {s}
                    </button>
                  )
                })}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Records list */}
      <div className="overflow-y-auto flex-1 min-h-0 space-y-2">
        {filtered.length === 0 ? (
          topLevel.length === 0 ? (
            <p className="text-[11px] text-muted-foreground font-mono text-center mt-8">
              No records yet.<br />Add intel, findings, or notes.
            </p>
          ) : (
            <p className="text-[11px] text-muted-foreground font-mono text-center mt-8">
              No records match your filters.
            </p>
          )
        ) : filtered.map(r => {
          const Icon = RECORD_ICONS[r.type] ?? FileText
          const StatusIcon = r.status ? STATUS_ICONS[r.status].icon : null
          return (
            <button
              key={r.id}
              onClick={() => onOpen(r.id)}
              className={`w-full text-left border border-border rounded p-3 hover:border-accent/40 hover:bg-accent/5 transition-colors group ${
                r.pinned ? "border-yellow-400/30 bg-yellow-400/5" : ""
              }`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-start gap-2 min-w-0 flex-1">
                  <Icon size={12} className={`mt-0.5 shrink-0 ${RECORD_COLORS[r.type]}`} />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-1.5">
                      {r.pinned && <Star size={10} className="text-yellow-400 fill-yellow-400 flex-shrink-0" />}
                      <p className="text-[12px] font-medium text-foreground truncate">{r.title}</p>
                    </div>
                    {r.content && (
                      <p className="text-[11px] text-muted-foreground mt-0.5 line-clamp-2">{r.content}</p>
                    )}
                    <div className="flex items-center gap-2 mt-1.5 flex-wrap">
                      {StatusIcon && r.status && (
                        <span className={`flex items-center gap-0.5 text-[10px] font-mono ${STATUS_ICONS[r.status].className}`}>
                          <StatusIcon size={9} />
                          {r.status}
                        </span>
                      )}
                      <span className="text-[10px] font-mono text-muted-foreground">{r.type}</span>
                      {r.source && <span className="text-[10px] font-mono text-muted-foreground">via {r.source}</span>}
                      <span className="text-[10px] text-muted-foreground ml-auto">{timeAgo(r.created_at)}</span>
                    </div>
                  </div>
                </div>
              </div>
            </button>
          )
        })}
      </div>
    </div>
  )
}
