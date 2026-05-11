// /api/oauth/clickup/lists?connection_id=...
//
// Fetches live ClickUp data (spaces → folders → lists) for a connection,
// flattened so the settings page can render a single dropdown / picker.
// Authenticated via the shared cookie + arena_connections row ownership.

import { NextRequest, NextResponse } from "next/server"
import { getActiveAuthId } from "@/lib/auth/session"
import { getServiceClient } from "@/lib/supabase/service"
import { CLICKUP_API_BASE, clickupAuthHeader } from "@/lib/oauth/clickup"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

type ListEntry = {
  id: string
  name: string
  spaceName: string
  folderName: string | null
}

export async function GET(req: NextRequest) {
  const userId = await getActiveAuthId()
  if (!userId) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const connectionId = req.nextUrl.searchParams.get("connection_id")
  const teamIdOverride = req.nextUrl.searchParams.get("team_id")
  if (!connectionId) return NextResponse.json({ error: "connection_id required" }, { status: 400 })

  const supabase = getServiceClient()
  const { data: conn } = await supabase
    .from("arena_connections")
    .select("credentials, config")
    .eq("id", connectionId)
    .eq("user_id", userId)
    .eq("provider", "clickup")
    .maybeSingle()
  if (!conn) return NextResponse.json({ error: "Connection not found" }, { status: 404 })

  const accessToken = (conn.credentials as Record<string, string> | null)?.access_token
  if (!accessToken) return NextResponse.json({ error: "Connection has no access token — re-authorize" }, { status: 400 })

  const teamId = teamIdOverride
    || (conn.config as Record<string, unknown> | null)?.default_team_id as string | undefined
  if (!teamId) return NextResponse.json({ error: "No team selected on this connection" }, { status: 400 })

  // Walk the workspace: spaces → folders → folder lists + folderless lists.
  const headers = { Authorization: clickupAuthHeader(accessToken) }
  const flat: ListEntry[] = []
  try {
    const spacesRes = await fetch(`${CLICKUP_API_BASE}/team/${teamId}/space?archived=false`, { headers })
    if (!spacesRes.ok) {
      const detail = await spacesRes.text().catch(() => `HTTP ${spacesRes.status}`)
      return NextResponse.json({ error: `ClickUp spaces fetch failed: ${detail.slice(0, 200)}` }, { status: 502 })
    }
    const { spaces = [] } = await spacesRes.json() as { spaces?: Array<{ id: string; name: string }> }

    // For each space, fetch folders (which contain lists) AND folderless lists in parallel.
    await Promise.all(spaces.map(async (sp) => {
      const [foldersRes, looseListsRes] = await Promise.all([
        fetch(`${CLICKUP_API_BASE}/space/${sp.id}/folder?archived=false`, { headers }),
        fetch(`${CLICKUP_API_BASE}/space/${sp.id}/list?archived=false`, { headers }),
      ])
      if (foldersRes.ok) {
        const { folders = [] } = await foldersRes.json() as {
          folders?: Array<{ name: string; lists?: Array<{ id: string; name: string }> }>
        }
        for (const f of folders) {
          for (const l of f.lists ?? []) {
            flat.push({ id: l.id, name: l.name, spaceName: sp.name, folderName: f.name })
          }
        }
      }
      if (looseListsRes.ok) {
        const { lists = [] } = await looseListsRes.json() as { lists?: Array<{ id: string; name: string }> }
        for (const l of lists) {
          flat.push({ id: l.id, name: l.name, spaceName: sp.name, folderName: null })
        }
      }
    }))
  } catch (err) {
    return NextResponse.json({ error: err instanceof Error ? err.message : "ClickUp probe failed" }, { status: 502 })
  }

  // Sort: spaceName, then folderName (null last), then list name
  flat.sort((a, b) => {
    if (a.spaceName !== b.spaceName) return a.spaceName.localeCompare(b.spaceName)
    if ((a.folderName ?? "") !== (b.folderName ?? "")) return (a.folderName ?? "￿").localeCompare(b.folderName ?? "￿")
    return a.name.localeCompare(b.name)
  })

  return NextResponse.json({ lists: flat })
}
