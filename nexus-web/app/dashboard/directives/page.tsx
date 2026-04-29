"use client"

import { useState, useEffect, useCallback } from "react"
import { Plus, Zap, Shield, Trash2, ToggleLeft, ToggleRight, Pencil, X, Check, ChevronUp, ChevronDown } from "lucide-react"

type DirectiveType = "directive" | "protocol"
type TargetSystem = "all" | "operations" | "agents" | "map" | "team" | "eve"

interface Directive {
  id: string
  type: DirectiveType
  title: string
  content: string
  is_active: boolean
  priority: number
  target: TargetSystem
  created_at: string
}

const TARGET_OPTIONS: { value: TargetSystem; label: string }[] = [
  { value: "all",        label: "All Systems" },
  { value: "eve",        label: "Eve (core behavior)" },
  { value: "operations", label: "Operations" },
  { value: "agents",     label: "Agents" },
  { value: "map",        label: "Nexus Map" },
  { value: "team",       label: "Team" },
]

const TYPE_META = {
  directive: {
    label: "Directive",
    description: "Hard rules Eve follows in every conversation. Injected at the top of her system prompt.",
    icon: Shield,
    color: "text-primary border-primary/30 bg-primary/5",
    activeColor: "bg-primary/10 border-primary/40",
  },
  protocol: {
    label: "Protocol",
    description: "Rules for how Eve interacts with a specific system or context.",
    icon: Zap,
    color: "text-amber-400 border-amber-400/30 bg-amber-400/5",
    activeColor: "bg-amber-400/10 border-amber-400/40",
  },
}

function EmptyState({ type, onAdd }: { type: DirectiveType; onAdd: () => void }) {
  const meta = TYPE_META[type]
  const Icon = meta.icon
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      <div className="w-12 h-12 rounded-xl border border-border flex items-center justify-center mb-4 bg-muted/40">
        <Icon size={20} className="text-muted-foreground" />
      </div>
      <p className="text-sm font-medium text-foreground mb-1">No {meta.label}s yet</p>
      <p className="text-xs text-muted-foreground mb-6 max-w-xs">{meta.description}</p>
      <button onClick={onAdd}
        className="flex items-center gap-2 px-4 py-2 text-xs font-semibold border border-border rounded-lg text-muted-foreground hover:text-foreground hover:border-primary/40 transition-colors">
        <Plus size={13} /> Add {meta.label}
      </button>
    </div>
  )
}

interface EditFormProps {
  type: DirectiveType
  initial?: Partial<Directive>
  onSave: (d: Partial<Directive>) => void
  onCancel: () => void
}

function EditForm({ type, initial, onSave, onCancel }: EditFormProps) {
  const [title, setTitle]     = useState(initial?.title ?? "")
  const [content, setContent] = useState(initial?.content ?? "")
  const [priority, setPriority] = useState(initial?.priority ?? 0)
  const [target, setTarget]   = useState<TargetSystem>(initial?.target ?? "all")

  return (
    <div className="border border-border rounded-xl bg-card p-5 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-muted-foreground uppercase tracking-widest">
          {initial?.id ? "Edit" : "New"} {TYPE_META[type].label}
        </span>
        <button onClick={onCancel} className="text-muted-foreground hover:text-foreground transition-colors">
          <X size={15} />
        </button>
      </div>

      <div className="flex flex-col gap-1.5">
        <label className="text-xs font-medium text-muted-foreground">Title</label>
        <input
          value={title}
          onChange={e => setTitle(e.target.value)}
          placeholder={type === "directive" ? "e.g. Never apologize" : "e.g. Operations entry format"}
          className="w-full bg-background border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary/40"
        />
      </div>

      <div className="flex flex-col gap-1.5">
        <label className="text-xs font-medium text-muted-foreground">
          {type === "directive" ? "Rule" : "Protocol instructions"}
        </label>
        <textarea
          value={content}
          onChange={e => setContent(e.target.value)}
          rows={4}
          placeholder={type === "directive"
            ? "Write the rule Eve must follow. Be precise — she takes this literally."
            : "Describe exactly how Eve should interact with this system."}
          className="w-full bg-background border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary/40 resize-none font-mono leading-relaxed"
        />
      </div>

      <div className="flex gap-4">
        {type === "protocol" && (
          <div className="flex flex-col gap-1.5 flex-1">
            <label className="text-xs font-medium text-muted-foreground">Target System</label>
            <select value={target} onChange={e => setTarget(e.target.value as TargetSystem)}
              className="w-full bg-background border border-border rounded-lg px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary/40">
              {TARGET_OPTIONS.map(o => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>
        )}

        <div className="flex flex-col gap-1.5 w-28">
          <label className="text-xs font-medium text-muted-foreground">Priority</label>
          <input
            type="number"
            value={priority}
            onChange={e => setPriority(parseInt(e.target.value) || 0)}
            min={0}
            max={100}
            className="w-full bg-background border border-border rounded-lg px-3 py-2 text-sm text-foreground focus:outline-none focus:ring-1 focus:ring-primary/40"
          />
          <span className="text-[10px] text-muted-foreground">Higher = injected first</span>
        </div>
      </div>

      <div className="flex justify-end gap-2 pt-1">
        <button onClick={onCancel}
          className="px-4 py-2 text-xs font-medium text-muted-foreground border border-border rounded-lg hover:text-foreground transition-colors">
          Cancel
        </button>
        <button
          onClick={() => { if (title.trim() && content.trim()) onSave({ title, content, priority, target, type }) }}
          disabled={!title.trim() || !content.trim()}
          className="flex items-center gap-1.5 px-4 py-2 text-xs font-semibold bg-primary text-primary-foreground rounded-lg hover:opacity-90 transition-opacity disabled:opacity-40"
        >
          <Check size={13} /> Save {TYPE_META[type].label}
        </button>
      </div>
    </div>
  )
}

interface DirectiveCardProps {
  item: Directive
  onToggle: (id: string, active: boolean) => void
  onDelete: (id: string) => void
  onEdit: (item: Directive) => void
  onPriority: (id: string, delta: number) => void
}

function DirectiveCard({ item, onToggle, onDelete, onEdit, onPriority }: DirectiveCardProps) {
  const meta = TYPE_META[item.type]
  const Icon = meta.icon
  return (
    <div className={`border rounded-xl p-4 transition-all ${item.is_active ? meta.activeColor : "border-border bg-card opacity-50"}`}>
      <div className="flex items-start gap-3">
        <div className={`mt-0.5 p-1.5 rounded-lg border ${meta.color} flex-shrink-0`}>
          <Icon size={13} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap mb-1">
            <span className="text-sm font-semibold text-foreground">{item.title}</span>
            {item.type === "protocol" && item.target !== "all" && (
              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded border border-border text-muted-foreground bg-muted/40">
                {item.target}
              </span>
            )}
            <span className="text-[10px] font-mono text-muted-foreground ml-auto">P{item.priority}</span>
          </div>
          <p className="text-xs text-muted-foreground leading-relaxed font-mono whitespace-pre-wrap">{item.content}</p>
        </div>
      </div>

      <div className="flex items-center gap-1 mt-3 pt-3 border-t border-border/50">
        <button onClick={() => onToggle(item.id, !item.is_active)}
          className="flex items-center gap-1.5 text-[11px] text-muted-foreground hover:text-foreground transition-colors px-2 py-1 rounded hover:bg-muted/60">
          {item.is_active
            ? <ToggleRight size={14} className="text-primary" />
            : <ToggleLeft size={14} />}
          {item.is_active ? "Active" : "Inactive"}
        </button>
        <button onClick={() => onEdit(item)}
          className="flex items-center gap-1.5 text-[11px] text-muted-foreground hover:text-foreground transition-colors px-2 py-1 rounded hover:bg-muted/60">
          <Pencil size={12} /> Edit
        </button>
        <div className="flex items-center ml-auto gap-0.5">
          <button onClick={() => onPriority(item.id, 10)}
            className="p-1 text-muted-foreground hover:text-foreground rounded transition-colors hover:bg-muted/60" title="Increase priority">
            <ChevronUp size={13} />
          </button>
          <button onClick={() => onPriority(item.id, -10)}
            className="p-1 text-muted-foreground hover:text-foreground rounded transition-colors hover:bg-muted/60" title="Decrease priority">
            <ChevronDown size={13} />
          </button>
          <button onClick={() => onDelete(item.id)}
            className="p-1 text-muted-foreground hover:text-destructive rounded transition-colors hover:bg-destructive/10 ml-1">
            <Trash2 size={13} />
          </button>
        </div>
      </div>
    </div>
  )
}

export default function DirectivesPage() {
  const [directives, setDirectives] = useState<Directive[]>([])
  const [loading, setLoading]       = useState(true)
  const [activeTab, setActiveTab]   = useState<DirectiveType>("directive")
  const [adding, setAdding]         = useState(false)
  const [editing, setEditing]       = useState<Directive | null>(null)
  const [saving, setSaving]         = useState(false)
  const [saveError, setSaveError]   = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const res = await fetch("/api/eve/directives")
    if (res.ok) {
      const json = await res.json()
      setDirectives(json.directives ?? [])
    }
    setLoading(false)
  }, [])

  useEffect(() => { load() }, [load])

  const filtered = directives.filter(d => d.type === activeTab)
  const activeCount = directives.filter(d => d.is_active).length

  async function handleSave(data: Partial<Directive>) {
    setSaving(true)
    setSaveError(null)
    try {
      if (editing?.id) {
        const res = await fetch("/api/eve/directives", {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: editing.id, ...data }),
        })
        const json = await res.json()
        if (!res.ok) { setSaveError(json.error ?? `Error ${res.status}`); setSaving(false); return }
        setDirectives(prev => prev.map(d => d.id === editing.id ? json.directive : d))
        setEditing(null)
      } else {
        const res = await fetch("/api/eve/directives", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ ...data, type: activeTab }),
        })
        const json = await res.json()
        if (!res.ok) { setSaveError(json.error ?? `Error ${res.status}`); setSaving(false); return }
        setDirectives(prev => [json.directive, ...prev])
        setAdding(false)
      }
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : "Unknown error")
    }
    setSaving(false)
  }

  async function handleToggle(id: string, is_active: boolean) {
    const res = await fetch("/api/eve/directives", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, is_active }),
    })
    if (res.ok) {
      const json = await res.json()
      setDirectives(prev => prev.map(d => d.id === id ? json.directive : d))
    }
  }

  async function handleDelete(id: string) {
    const res = await fetch("/api/eve/directives", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id }),
    })
    if (res.ok) setDirectives(prev => prev.filter(d => d.id !== id))
  }

  async function handlePriority(id: string, delta: number) {
    const item = directives.find(d => d.id === id)
    if (!item) return
    const newPriority = Math.max(0, item.priority + delta)
    const res = await fetch("/api/eve/directives", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, priority: newPriority }),
    })
    if (res.ok) {
      const json = await res.json()
      setDirectives(prev => prev.map(d => d.id === id ? json.directive : d))
    }
  }

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-4 md:px-8 py-4 md:py-6 border-b border-border flex flex-col md:flex-row md:items-center md:justify-between gap-3 md:gap-0 flex-shrink-0">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-[10px] font-mono tracking-widest uppercase text-muted-foreground">Eve</span>
            <span className="text-[10px] text-muted-foreground">/</span>
            <span className="text-[10px] font-mono tracking-widest uppercase text-foreground">Core Intelligence</span>
          </div>
          <h1 className="text-lg md:text-xl font-bold text-foreground tracking-tight">Directives & Protocols</h1>
          <p className="text-xs md:text-sm text-muted-foreground mt-0.5">
            Define how Eve thinks, speaks, and interacts with every system in Nexus.
          </p>
        </div>
        <div className="flex items-center gap-2 md:gap-3">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-border bg-muted/30">
            <div className={`w-1.5 h-1.5 rounded-full ${activeCount > 0 ? "bg-primary animate-pulse" : "bg-muted-foreground"}`} />
            <span className="text-xs text-muted-foreground font-mono">{activeCount} active</span>
          </div>
          <button
            onClick={() => { setAdding(true); setEditing(null) }}
            className="flex items-center gap-2 px-3 md:px-4 py-2 bg-primary text-primary-foreground text-xs font-semibold rounded-lg hover:opacity-90 transition-opacity whitespace-nowrap"
          >
            <Plus size={14} />
            <span className="hidden sm:inline">Add </span>
            {activeTab === "directive" ? "Directive" : "Protocol"}
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="px-4 md:px-8 pt-4 flex gap-1 border-b border-border flex-shrink-0">
        {(["directive", "protocol"] as DirectiveType[]).map(t => {
          const meta = TYPE_META[t]
          const Icon = meta.icon
          const count = directives.filter(d => d.type === t).length
          return (
            <button key={t}
              onClick={() => { setActiveTab(t); setAdding(false); setEditing(null) }}
              className={`flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors ${
                activeTab === t
                  ? "border-primary text-foreground"
                  : "border-transparent text-muted-foreground hover:text-foreground"
              }`}
            >
              <Icon size={14} />
              {meta.label}s
              {count > 0 && (
                <span className="text-[10px] font-mono px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground">{count}</span>
              )}
            </button>
          )
        })}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto px-4 md:px-8 py-4 md:py-6 pb-24 md:pb-6">
        {/* Description bar */}
        <div className="mb-6 p-4 rounded-xl border border-border bg-muted/20">
          <p className="text-xs text-muted-foreground leading-relaxed">
            {activeTab === "directive"
              ? "Directives are injected at the top of Eve's system prompt and govern her core behavior across all conversations. Higher priority directives are loaded first. Active directives take effect immediately on the next message."
              : "Protocols define how Eve interacts with specific Nexus systems — Operations, Agents, the Map, Team, or globally. They are injected into Eve's context when she is operating in that system's scope."}
          </p>
        </div>

        {/* Save error banner */}
        {saveError && (
          <div className="mb-4 p-3 rounded-lg border border-destructive/40 bg-destructive/10 text-xs text-destructive flex items-center justify-between">
            <span>Failed to save: {saveError}</span>
            <button onClick={() => setSaveError(null)} className="ml-4 text-destructive/70 hover:text-destructive">
              <X size={13} />
            </button>
          </div>
        )}

        {/* Add/Edit form */}
        {(adding && !editing) && (
          <div className="mb-4">
            <EditForm
              type={activeTab}
              onSave={handleSave}
              onCancel={() => { setAdding(false); setSaveError(null) }}
            />
          </div>
        )}

        {/* List */}
        {loading ? (
          <div className="flex flex-col gap-3">
            {[1, 2, 3].map(i => (
              <div key={i} className="h-28 rounded-xl border border-border bg-muted/20 animate-pulse" />
            ))}
          </div>
        ) : filtered.length === 0 && !adding ? (
          <EmptyState type={activeTab} onAdd={() => setAdding(true)} />
        ) : (
          <div className="flex flex-col gap-3">
            {filtered
              .sort((a, b) => b.priority - a.priority)
              .map(item => editing?.id === item.id ? (
                <EditForm
                  key={item.id}
                  type={activeTab}
                  initial={editing}
                  onSave={handleSave}
                  onCancel={() => setEditing(null)}
                />
              ) : (
                <DirectiveCard
                  key={item.id}
                  item={item}
                  onToggle={handleToggle}
                  onDelete={handleDelete}
                  onEdit={setEditing}
                  onPriority={handlePriority}
                />
              ))
            }
          </div>
        )}
      </div>
    </div>
  )
}
