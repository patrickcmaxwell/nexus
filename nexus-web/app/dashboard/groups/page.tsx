"use client"

import { useState, useEffect, useCallback, useRef } from "react"
import { Users, Plus, X, Globe, ShieldCheck, Settings, Trash2, Edit2, Loader2, Save, MessageSquare, Send, ChevronLeft } from "lucide-react"

interface GroupMember {
  human_id: string
  joined_at: string
  role?: string
  humans?: {
    display_name: string
    handle: string | null
  } | null
}

interface Group {
  id: string
  name: string
  description: string
  created_by: string
  created_at: string
  group_members: GroupMember[]
}

interface GroupMessage {
  id: string
  content: string
  created_at: string
  human_id: string
  humans?: { display_name: string; handle: string | null } | null
}

export default function GroupsPage() {
  const [groups, setGroups] = useState<Group[]>([])
  const [humanId, setHumanId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const [showModal, setShowModal] = useState(false)
  const [newName, setNewName] = useState("")
  const [newDesc, setNewDesc] = useState("")
  const [creating, setCreating] = useState(false)

  const [managingGroup, setManagingGroup] = useState<Group | null>(null)
  const [editingGroupInfo, setEditingGroupInfo] = useState(false)
  const [editName, setEditName] = useState("")
  const [editDesc, setEditDesc] = useState("")
  const [savingEdit, setSavingEdit] = useState(false)

  // Chat panel state
  const [chatGroup, setChatGroup] = useState<Group | null>(null)
  const [messages, setMessages] = useState<GroupMessage[]>([])
  const [messagesLoading, setMessagesLoading] = useState(false)
  const [messageInput, setMessageInput] = useState("")
  const [sending, setSending] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const loadGroups = useCallback(async () => {
    setLoading(true)
    const res = await fetch("/api/groups")
    if (res.ok) {
      const data = await res.json()
      setGroups(data.groups ?? [])
      setHumanId(data.currentHumanId)
    }
    setLoading(false)
  }, [])

  useEffect(() => { loadGroups() }, [loadGroups])

  // Chat: load messages + start polling
  const openChat = useCallback(async (group: Group) => {
    setChatGroup(group)
    setMessages([])
    setMessagesLoading(true)
    const res = await fetch(`/api/groups/${group.id}/messages`)
    if (res.ok) {
      const data = await res.json()
      setMessages(data.messages ?? [])
    }
    setMessagesLoading(false)

    if (pollRef.current) clearInterval(pollRef.current)
    pollRef.current = setInterval(async () => {
      const r = await fetch(`/api/groups/${group.id}/messages`)
      if (r.ok) {
        const d = await r.json()
        setMessages(d.messages ?? [])
      }
    }, 4000)
  }, [])

  const closeChat = useCallback(() => {
    setChatGroup(null)
    setMessages([])
    setMessageInput("")
    if (pollRef.current) { clearInterval(pollRef.current); pollRef.current = null }
  }, [])

  useEffect(() => () => { if (pollRef.current) clearInterval(pollRef.current) }, [])

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages])

  async function sendMessage() {
    if (!chatGroup || !messageInput.trim() || sending) return
    setSending(true)
    const content = messageInput.trim()
    setMessageInput("")
    const res = await fetch(`/api/groups/${chatGroup.id}/messages`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content }),
    })
    if (res.ok) {
      const msg = await res.json()
      setMessages(prev => [...prev, msg])
    }
    setSending(false)
  }

  async function createGroup() {
    if (!newName.trim()) return
    setCreating(true)
    const res = await fetch("/api/groups", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: newName, description: newDesc }),
    })
    setCreating(false)
    if (res.ok) {
      setNewName("")
      setNewDesc("")
      setShowModal(false)
      loadGroups()
    } else {
      const err = await res.json()
      alert("Failed to create group: " + (err.error || "Unknown error"))
    }
  }

  async function joinGroup(groupId: string) {
    const res = await fetch("/api/groups/join", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ group_id: groupId }),
    })
    if (res.ok) loadGroups()
  }

  async function leaveGroup(groupId: string) {
    const res = await fetch("/api/groups/join", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ group_id: groupId }),
    })
    if (res.ok) loadGroups()
  }

  function openManage(group: Group) {
    setManagingGroup(group)
    setEditName(group.name)
    setEditDesc(group.description)
    setEditingGroupInfo(false)
  }

  async function kickMember(groupId: string, targetHumanId: string) {
    if (!confirm("Remove this member from the group?")) return
    const res = await fetch("/api/groups/manage", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ group_id: groupId, target_human_id: targetHumanId }),
    })
    if (res.ok) {
      setManagingGroup(prev => prev ? { ...prev, group_members: prev.group_members.filter(m => m.human_id !== targetHumanId) } : null)
      loadGroups()
    } else {
      const err = await res.json()
      alert("Failed to kick: " + (err.error || "Unknown error"))
    }
  }

  async function deleteGroup(groupId: string) {
    if (!confirm("Are you sure you want to permanently delete this group?")) return
    const res = await fetch("/api/groups", {
      method: "DELETE",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: groupId }),
    })
    if (res.ok) {
      setManagingGroup(null)
      loadGroups()
    } else {
      const err = await res.json()
      alert("Failed to delete group: " + (err.error || "Unknown error"))
    }
  }

  async function saveGroupEdits() {
    if (!managingGroup) return
    setSavingEdit(true)
    const res = await fetch("/api/groups", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: managingGroup.id, name: editName, description: editDesc }),
    })
    setSavingEdit(false)
    if (res.ok) {
      setManagingGroup({ ...managingGroup, name: editName, description: editDesc })
      setEditingGroupInfo(false)
      loadGroups()
    } else {
      const err = await res.json()
      alert("Failed to update group: " + (err.error || "Unknown error"))
    }
  }

  function formatTime(iso: string) {
    const d = new Date(iso)
    return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  }

  return (
    <div className="p-6 md:p-10 max-w-5xl mx-auto space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-foreground flex items-center gap-2">
            <Globe className="text-accent" size={24} />
            Groups Ecosystem
          </h1>
          <p className="text-sm text-muted-foreground mt-1 max-w-2xl">
            Join groups to collaborate and share internal Operations, Agents, and Directives.
          </p>
        </div>
        <button
          onClick={() => setShowModal(true)}
          className="flex items-center gap-2 bg-accent text-accent-foreground px-4 py-2 rounded font-medium hover:opacity-90 transition-opacity whitespace-nowrap self-start md:self-auto"
        >
          <Plus size={16} /> Spawn Group
        </button>
      </div>

      {loading ? (
        <div className="py-20 flex justify-center">
          <p className="text-muted-foreground font-mono text-sm animate-pulse">Scanning groups...</p>
        </div>
      ) : groups.length === 0 ? (
        <div className="border border-border rounded-lg p-12 text-center bg-card">
          <Users size={32} className="mx-auto text-muted-foreground opacity-50 mb-4" />
          <h3 className="text-foreground font-medium mb-1">No groups found</h3>
          <p className="text-sm text-muted-foreground">Spawn the first ecosystem group to begin collaborating.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {groups.map((group) => {
            const isMember = group.group_members.some(m => m.human_id === humanId)
            const isOwner = group.created_by === humanId

            return (
              <div key={group.id} className="relative bg-card border border-border rounded-xl p-5 hover:border-accent/40 transition-colors flex flex-col group/card shadow-[0_4px_24px_rgba(0,0,0,0.4)]">
                <div className="flex justify-between items-start mb-3">
                  <h3 className="text-lg font-semibold text-foreground truncate pr-4">{group.name}</h3>
                  <div className="flex gap-2 shrink-0">
                    {isMember && (
                       <div className="bg-accent/10 text-accent text-[10px] uppercase tracking-wider font-mono px-2 py-0.5 rounded border border-accent/20 flex items-center gap-1">
                         <ShieldCheck size={10} /> Joined
                       </div>
                    )}
                    {isOwner && (
                      <button
                        onClick={() => openManage(group)}
                        className="text-muted-foreground hover:text-foreground transition-colors p-1 -m-1"
                        title="Manage Group"
                      >
                        <Settings size={14} />
                      </button>
                    )}
                  </div>
                </div>

                <p className="text-sm text-muted-foreground mb-6 flex-1">{group.description || "No description provided."}</p>

                <div className="flex items-center justify-between mt-auto pt-4 border-t border-border/50">
                  <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                    <Users size={14} className="opacity-70" />
                    <span className="font-mono">{group.group_members.length} Human{group.group_members.length !== 1 ? 's' : ''}</span>
                  </div>

                  <div className="flex items-center gap-2">
                    {isMember && (
                      <button
                        onClick={() => openChat(group)}
                        className="text-xs text-muted-foreground hover:text-foreground font-medium px-3 py-1.5 rounded bg-muted hover:bg-muted/80 transition-colors flex items-center gap-1"
                        title="Open group chat"
                      >
                        <MessageSquare size={12} /> Chat
                      </button>
                    )}
                    {isMember ? (
                      <button
                        onClick={() => leaveGroup(group.id)}
                        disabled={isOwner}
                        title={isOwner ? "Creator cannot leave the group directly" : ""}
                        className="text-xs text-destructive hover:text-destructive/80 font-medium px-3 py-1.5 rounded bg-destructive/10 hover:bg-destructive/20 transition-colors disabled:opacity-30 disabled:cursor-not-allowed"
                      >
                        Leave Group
                      </button>
                    ) : (
                      <button
                        onClick={() => joinGroup(group.id)}
                        className="text-xs text-accent hover:text-accent-foreground font-medium px-4 py-1.5 rounded bg-accent/10 hover:bg-accent transition-colors"
                      >
                        Join
                      </button>
                    )}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Chat Panel */}
      {chatGroup && (
        <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-card border border-border rounded-xl w-full max-w-lg shadow-2xl flex flex-col h-[80vh]">
            {/* Header */}
            <div className="flex items-center gap-3 px-5 py-4 border-b border-border flex-shrink-0">
              <button onClick={closeChat} className="text-muted-foreground hover:text-foreground transition-colors">
                <ChevronLeft size={18} />
              </button>
              <MessageSquare size={16} className="text-accent" />
              <h2 className="text-sm font-semibold text-foreground flex-1 truncate">{chatGroup.name}</h2>
              <button onClick={closeChat} className="text-muted-foreground hover:text-foreground transition-colors">
                <X size={18} />
              </button>
            </div>

            {/* Messages */}
            <div className="flex-1 overflow-y-auto px-5 py-4 space-y-3">
              {messagesLoading ? (
                <div className="flex justify-center py-10">
                  <Loader2 size={20} className="animate-spin text-muted-foreground" />
                </div>
              ) : messages.length === 0 ? (
                <div className="text-center py-12 text-muted-foreground text-sm">
                  No messages yet. Start the conversation.
                </div>
              ) : messages.map((msg, i) => {
                const isMe = msg.human_id === humanId
                const showSender = i === 0 || messages[i - 1].human_id !== msg.human_id
                return (
                  <div key={msg.id} className={`flex flex-col ${isMe ? "items-end" : "items-start"}`}>
                    {showSender && !isMe && (
                      <span className="text-[10px] font-mono text-muted-foreground mb-1 px-1">
                        {msg.humans?.display_name ?? "Unknown"}
                      </span>
                    )}
                    <div className={`max-w-[80%] px-3 py-2 rounded-xl text-sm ${
                      isMe
                        ? "bg-accent text-accent-foreground rounded-br-sm"
                        : "bg-muted text-foreground rounded-bl-sm"
                    }`}>
                      {msg.content}
                    </div>
                    <span className="text-[10px] text-muted-foreground mt-0.5 px-1">{formatTime(msg.created_at)}</span>
                  </div>
                )
              })}
              <div ref={messagesEndRef} />
            </div>

            {/* Input */}
            <div className="flex items-center gap-2 px-4 py-3 border-t border-border flex-shrink-0">
              <input
                value={messageInput}
                onChange={e => setMessageInput(e.target.value)}
                onKeyDown={e => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage() } }}
                placeholder="Message the group..."
                className="flex-1 bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50"
              />
              <button
                onClick={sendMessage}
                disabled={sending || !messageInput.trim()}
                className="p-2 rounded-lg bg-accent text-accent-foreground hover:opacity-80 transition-opacity disabled:opacity-40 disabled:cursor-not-allowed flex-shrink-0"
              >
                <Send size={16} />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Manage Group Modal */}
      {managingGroup && (
        <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-card border border-border rounded-xl w-full max-w-lg shadow-2xl p-4 sm:p-6 flex flex-col max-h-[90vh]">
            <div className="flex items-center justify-between mb-6 flex-shrink-0">
              <h2 className="text-lg font-semibold text-foreground flex items-center gap-2">
                <Settings className="text-accent" size={20} />
                Manage Group
              </h2>
              <button onClick={() => setManagingGroup(null)} className="text-muted-foreground hover:text-foreground transition-colors">
                <X size={20} />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto pr-2 space-y-6">
              {/* Info Section */}
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground font-mono">Details</h3>
                  {!editingGroupInfo ? (
                    <button onClick={() => setEditingGroupInfo(true)} className="text-xs text-accent hover:underline flex items-center gap-1">
                      <Edit2 size={10} /> Edit
                    </button>
                  ) : (
                    <button onClick={saveGroupEdits} disabled={savingEdit} className="text-xs text-emerald-400 hover:underline flex items-center gap-1 disabled:opacity-50">
                      {savingEdit ? <Loader2 size={10} className="animate-spin" /> : <Save size={10} />} Save
                    </button>
                  )}
                </div>

                {editingGroupInfo ? (
                  <div className="space-y-3 p-3 bg-muted/50 rounded-lg border border-border">
                    <input
                      value={editName}
                      onChange={e => setEditName(e.target.value)}
                      className="w-full bg-background border border-border rounded px-3 py-1.5 text-sm text-foreground focus:outline-none focus:border-accent/50"
                    />
                    <textarea
                      value={editDesc}
                      onChange={e => setEditDesc(e.target.value)}
                      rows={2}
                      className="w-full bg-background border border-border rounded px-3 py-1.5 text-sm text-foreground focus:outline-none focus:border-accent/50 resize-none"
                    />
                  </div>
                ) : (
                  <div className="p-3 bg-muted/30 rounded-lg border border-border">
                    <p className="font-semibold text-foreground">{managingGroup.name}</p>
                    <p className="text-sm text-muted-foreground mt-1">{managingGroup.description}</p>
                  </div>
                )}
              </div>

              {/* Members List */}
              <div className="space-y-3">
                <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground font-mono">Members ({managingGroup.group_members.length})</h3>
                <div className="space-y-2">
                  {managingGroup.group_members.map(member => (
                    <div key={member.human_id} className="flex items-center justify-between p-3 rounded-lg border border-border bg-card hover:bg-muted/30 transition-colors">
                      <div>
                        <p className="text-sm font-medium text-foreground">{member.humans?.display_name || "Unknown Human"}</p>
                        <div className="flex items-center gap-2 mt-0.5">
                          {member.humans?.handle && <span className="text-xs text-muted-foreground">@{member.humans.handle}</span>}
                          <span className="text-[10px] font-mono uppercase tracking-widest text-accent/70">{member.role || 'member'}</span>
                        </div>
                      </div>

                      {member.human_id !== humanId && (
                        <button
                          onClick={() => kickMember(managingGroup.id, member.human_id)}
                          className="text-muted-foreground hover:text-destructive p-1.5 rounded transition-colors"
                          title="Kick Member"
                        >
                          <X size={14} />
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            </div>

            <div className="mt-8 pt-4 border-t border-border flex justify-between items-center flex-shrink-0">
              <button
                onClick={() => deleteGroup(managingGroup.id)}
                className="text-xs text-destructive hover:text-destructive/80 flex items-center gap-1.5 px-3 py-1.5 rounded bg-destructive/10 hover:bg-destructive/20 transition-colors"
              >
                <Trash2 size={12} /> Delete Group
              </button>
              <button
                onClick={() => setManagingGroup(null)}
                className="text-sm bg-accent text-accent-foreground px-5 py-2 rounded-lg font-medium hover:bg-accent/80 transition-opacity"
               >
                Done
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Spawn Group Modal */}
      {showModal && (
        <div className="fixed inset-0 bg-background/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-card border border-border rounded-xl w-full max-w-md shadow-2xl p-6">
            <div className="flex items-center justify-between mb-6">
              <h2 className="text-lg font-semibold text-foreground flex items-center gap-2">
                <Users className="text-accent" size={20} />
                Spawn New Group
              </h2>
              <button onClick={() => setShowModal(false)} className="text-muted-foreground hover:text-foreground transition-colors">
                <X size={20} />
              </button>
            </div>

            <div className="space-y-4">
              <div className="space-y-1.5">
                <label className="text-[10px] font-mono text-muted-foreground uppercase tracking-widest">Designation</label>
                <input
                  value={newName}
                  onChange={e => setNewName(e.target.value)}
                  placeholder="e.g. Red Team, Operations, Analysis..."
                  className="w-full bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50"
                  autoFocus
                />
              </div>

              <div className="space-y-1.5">
                <label className="text-[10px] font-mono text-muted-foreground uppercase tracking-widest">Purpose (Optional)</label>
                <textarea
                  value={newDesc}
                  onChange={e => setNewDesc(e.target.value)}
                  placeholder="Defining characteristics or objectives..."
                  rows={3}
                  className="w-full bg-muted border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:border-accent/50 resize-none"
                />
              </div>
            </div>

            <div className="flex gap-3 mt-8">
              <button
                onClick={() => setShowModal(false)}
                className="flex-1 text-sm border border-border text-muted-foreground px-4 py-2.5 rounded-lg hover:bg-muted transition-colors"
               >
                Cancel
              </button>
              <button
                onClick={createGroup}
                disabled={creating || !newName.trim()}
                className="flex-1 text-sm bg-accent text-accent-foreground px-4 py-2.5 rounded-lg font-medium hover:bg-accent/80 transition-opacity disabled:opacity-50 disabled:cursor-not-allowed flex justify-center items-center gap-2"
              >
                {creating ? <span className="animate-pulse">Spawning...</span> : "Spawn Group"}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
