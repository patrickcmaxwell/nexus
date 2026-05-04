import React, { useEffect, useRef, useState } from 'react'
import { Send, Users, Plus, Trash2, UserPlus } from 'lucide-react'

const NEXUS = 'http://localhost:3000'

interface Member { human_id: string; role: string; joined_at: string; humans?: { display_name: string; handle: string } }
interface Group { id: string; name: string; description: string; created_by: string; group_members?: Member[] }
interface Message { id: string; content: string; created_at: string; human_id: string; humans?: { display_name: string; handle: string } }

function apiHeaders(sessionId: string) {
  return { 'Content-Type': 'application/json', Authorization: `Bearer ${sessionId}` }
}

export function GroupsView({ sessionId }: { sessionId: string }) {
  const [groups, setGroups]     = useState<Group[]>([])
  const [loading, setLoading]   = useState(true)
  const [selected, setSelected] = useState<Group | null>(null)
  const [messages, setMessages] = useState<Message[]>([])
  const [myId, setMyId]         = useState<string | null>(null)
  const [input, setInput]       = useState('')
  const [sending, setSending]   = useState(false)
  const [showCreate, setShowCreate] = useState(false)
  const [newGroupName, setNewGroupName]   = useState('')
  const [newGroupDesc, setNewGroupDesc]   = useState('')
  const [creating, setCreating] = useState(false)
  const [tab, setTab]           = useState<'chat' | 'members'>('chat')
  const bottomRef               = useRef<HTMLDivElement>(null)

  const loadGroups = () =>
    fetch(`${NEXUS}/api/groups`, { headers: apiHeaders(sessionId) })
      .then(r => r.json())
      .then(d => {
        setGroups(Array.isArray(d) ? d : d.groups ?? [])
        if (d.currentHumanId) setMyId(d.currentHumanId)
        setLoading(false)
      })
      .catch(() => setLoading(false))

  useEffect(() => { loadGroups() }, [sessionId])

  useEffect(() => {
    if (!selected) return
    const load = () =>
      fetch(`${NEXUS}/api/groups/${selected.id}/messages`, { headers: apiHeaders(sessionId) })
        .then(r => r.json())
        .then(d => {
          setMessages(Array.isArray(d) ? d : d.messages ?? [])
          if (d.currentHumanId && !myId) setMyId(d.currentHumanId)
        })
        .catch(() => {})
    load()
    const t = setInterval(load, 4000)
    return () => clearInterval(t)
  }, [selected, sessionId])

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  async function sendMessage() {
    if (!input.trim() || !selected || sending) return
    setSending(true)
    try {
      await fetch(`${NEXUS}/api/groups/${selected.id}/messages`, {
        method: 'POST',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ content: input.trim() }),
      })
      setInput('')
      const d = await fetch(`${NEXUS}/api/groups/${selected.id}/messages`, { headers: apiHeaders(sessionId) }).then(r => r.json())
      setMessages(Array.isArray(d) ? d : d.messages ?? [])
    } finally { setSending(false) }
  }

  async function createGroup() {
    if (!newGroupName.trim()) return
    setCreating(true)
    try {
      const res = await fetch(`${NEXUS}/api/groups`, {
        method: 'POST',
        headers: apiHeaders(sessionId),
        body: JSON.stringify({ name: newGroupName.trim(), description: newGroupDesc.trim() }),
      })
      if (res.ok) {
        setShowCreate(false)
        setNewGroupName('')
        setNewGroupDesc('')
        await loadGroups()
      }
    } finally { setCreating(false) }
  }

  async function deleteGroup(id: string) {
    if (!confirm('Delete this group and all its messages?')) return
    await fetch(`${NEXUS}/api/groups`, {
      method: 'DELETE',
      headers: apiHeaders(sessionId),
      body: JSON.stringify({ id }),
    })
    setGroups(prev => prev.filter(g => g.id !== id))
    if (selected?.id === id) { setSelected(null); setMessages([]) }
  }

  const joinCode = (invite: string) => `${NEXUS}/join/${invite}`

  return (
    <div className="flex-1 flex overflow-hidden">

      {/* ── Group list ───────────────────────────────────────────────────── */}
      <div className="w-64 flex-shrink-0 flex flex-col border-r border-white/[0.04] overflow-hidden">
        <div className="px-5 py-4 border-b border-white/[0.04] flex items-center justify-between">
          <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/30 uppercase">Groups</h2>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1.5 border border-[#00d4ff]/20 text-[#00d4ff]/60 hover:bg-[#00d4ff]/10 rounded-lg transition-all"
          >
            <Plus size={11} /> New
          </button>
        </div>
        <div className="flex-1 overflow-y-auto">
          {loading && <p className="text-[11px] font-mono text-white/20 p-5">Loading...</p>}
          {!loading && groups.length === 0 && (
            <p className="text-[11px] font-mono text-white/20 p-5">No groups yet. Create one.</p>
          )}
          {groups.map(g => (
            <button
              key={g.id}
              onClick={() => { setSelected(g); setMessages([]); setTab('chat') }}
              className={`w-full text-left px-5 py-3.5 border-b border-white/[0.03] hover:bg-white/3 transition-colors ${selected?.id === g.id ? 'bg-white/4' : ''}`}
            >
              <div className="flex items-center gap-2">
                <Users size={13} className="text-white/25 flex-shrink-0" />
                <span className="text-sm text-white/75 truncate">{g.name}</span>
                <span className="text-[10px] text-white/20 ml-auto">{g.group_members?.length ?? 0}</span>
              </div>
              {g.description && (
                <p className="text-[10px] text-white/25 mt-1 truncate pl-5">{g.description}</p>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* ── Chat / Members panel ─────────────────────────────────────────── */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {!selected ? (
          <div className="flex-1 flex items-center justify-center">
            <p className="text-[11px] font-mono text-white/15 tracking-widest uppercase">Select a group</p>
          </div>
        ) : (
          <>
            {/* Header */}
            <div className="px-6 py-3.5 border-b border-white/[0.04] flex items-center justify-between flex-shrink-0">
              <div className="flex items-center gap-4">
                <h3 className="text-sm text-white/70 font-medium">{selected.name}</h3>
                <div className="flex gap-1">
                  {(['chat', 'members'] as const).map(t => (
                    <button key={t} onClick={() => setTab(t)}
                      className={`text-[10px] font-mono uppercase px-2.5 py-1 rounded-lg transition-colors ${
                        tab === t ? 'bg-white/8 text-white/60' : 'text-white/25 hover:text-white/50'
                      }`}>
                      {t}
                    </button>
                  ))}
                </div>
              </div>
              <button
                onClick={() => deleteGroup(selected.id)}
                className="flex items-center gap-1.5 text-[10px] font-mono uppercase px-3 py-1 border border-red-500/20 text-red-400/40 hover:bg-red-500/10 hover:text-red-400 rounded-lg transition-all"
              >
                <Trash2 size={11} /> Delete
              </button>
            </div>

            {/* Chat tab */}
            {tab === 'chat' && (
              <>
                <div className="flex-1 overflow-y-auto px-6 py-4 space-y-3">
                  {messages.length === 0 && (
                    <p className="text-[11px] font-mono text-white/15 text-center mt-8">No messages yet.</p>
                  )}
                  {messages.map(m => {
                    const isMe = m.human_id === myId
                    return (
                      <div key={m.id} className={`flex flex-col gap-0.5 ${isMe ? 'items-end' : 'items-start'}`}>
                        <div className="flex items-center gap-2">
                          <span className="text-[10px] font-mono text-[#00d4ff]/60">
                            {m.humans?.display_name ?? m.humans?.handle ?? 'Unknown'}
                          </span>
                          <span className="text-[9px] text-white/15">
                            {new Date(m.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                        </div>
                        <div className={`max-w-[75%] px-4 py-2.5 rounded-2xl ${
                          isMe
                            ? 'bg-white/6 border border-white/10 rounded-tr-sm text-white/75'
                            : 'border border-[#00d4ff]/15 bg-[#00d4ff]/5 rounded-tl-sm text-white/80'
                        }`}>
                          <p className="text-sm leading-relaxed select-text cursor-text">{m.content}</p>
                        </div>
                      </div>
                    )
                  })}
                  <div ref={bottomRef} />
                </div>

                <div className="flex-shrink-0 px-6 pb-5 pt-3 border-t border-white/[0.04]">
                  <div className="flex items-center gap-2 bg-white/4 border border-white/8 rounded-xl px-4 py-2.5 focus-within:border-white/15 transition-colors">
                    <input
                      value={input}
                      onChange={e => setInput(e.target.value)}
                      onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); sendMessage() } }}
                      placeholder={`Message ${selected.name}...`}
                      disabled={sending}
                      className="flex-1 bg-transparent text-sm text-white/80 placeholder:text-white/18 focus:outline-none disabled:opacity-40"
                    />
                    <button onClick={sendMessage} disabled={!input.trim() || sending}
                      className="w-8 h-8 rounded-xl flex items-center justify-center text-white/30 hover:text-[#00d4ff] hover:bg-[#00d4ff]/10 disabled:opacity-20 disabled:cursor-not-allowed transition-all">
                      <Send size={14} />
                    </button>
                  </div>
                </div>
              </>
            )}

            {/* Members tab */}
            {tab === 'members' && (
              <div className="flex-1 overflow-y-auto p-6">
                <div className="space-y-2">
                  {(selected.group_members ?? []).map(m => (
                    <div key={m.human_id} className="flex items-center justify-between px-4 py-3 bg-white/3 border border-white/[0.05] rounded-xl">
                      <div>
                        <p className="text-sm text-white/75">{m.humans?.display_name ?? m.humans?.handle ?? 'Unknown'}</p>
                        {m.humans?.handle && <p className="text-[10px] text-white/30 font-mono">@{m.humans.handle}</p>}
                      </div>
                      <span className="text-[9px] font-mono uppercase px-2 py-0.5 border border-white/10 text-white/30 rounded">
                        {m.role}
                      </span>
                    </div>
                  ))}
                  {(selected.group_members ?? []).length === 0 && (
                    <p className="text-[11px] font-mono text-white/20 text-center mt-4">No members.</p>
                  )}
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* ── Create Modal ──────────────────────────────────────────────────── */}
      {showCreate && (
        <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50" onClick={() => setShowCreate(false)}>
          <div className="bg-[#0a0a0a] border border-white/10 rounded-2xl p-8 w-full max-w-md" onClick={e => e.stopPropagation()}>
            <h2 className="text-[11px] font-mono tracking-[0.3em] text-white/40 uppercase mb-6">Create Group</h2>
            <div className="space-y-4">
              <div>
                <p className="text-[10px] font-mono text-white/30 uppercase mb-1.5">Name *</p>
                <input autoFocus value={newGroupName} onChange={e => setNewGroupName(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && createGroup()}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="Group name" />
              </div>
              <div>
                <p className="text-[10px] font-mono text-white/30 uppercase mb-1.5">Description</p>
                <input value={newGroupDesc} onChange={e => setNewGroupDesc(e.target.value)}
                  className="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2.5 text-sm text-white/80 placeholder:text-white/20 focus:outline-none focus:border-white/25"
                  placeholder="Optional description" />
              </div>
            </div>
            <div className="flex justify-end gap-3 mt-6">
              <button onClick={() => setShowCreate(false)}
                className="px-4 py-2 text-[11px] font-mono uppercase text-white/30 hover:text-white/60 transition-colors">
                Cancel
              </button>
              <button onClick={createGroup} disabled={!newGroupName.trim() || creating}
                className="px-5 py-2 text-[11px] font-mono uppercase border border-[#00d4ff]/25 text-[#00d4ff]/70 hover:bg-[#00d4ff]/10 rounded-xl transition-all disabled:opacity-30">
                {creating ? 'Creating...' : 'Create Group'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
