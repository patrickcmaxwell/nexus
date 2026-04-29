import DashboardHome, { type Overview } from "@/components/dashboard/DashboardHome"
import { headers } from "next/headers"

// Server-side initial fetch of the dashboard overview. We call our own API
// route so the client gets a fully-populated first render (no flash of empty
// panels) and subsequent smart-polls go through the same endpoint.
async function fetchInitial(): Promise<Overview | null> {
  try {
    const h = await headers()
    const proto = h.get("x-forwarded-proto") ?? "http"
    const host = h.get("host") ?? "localhost:3000"
    const res = await fetch(`${proto}://${host}/api/dashboard/overview`, { cache: "no-store" })
    if (!res.ok) return null
    return (await res.json()) as Overview
  } catch {
    return null
  }
}

const EMPTY_OVERVIEW: Overview = {
  greeting: "Good day, sir. Systems initializing. Stand by.",
  suggestions: ["What's the objective?", "Start a new operation", "Show recent activity"],
  stats: { conversations: 0, memories: 0, operations: 0, agents: 0, records: 0, activeOperations: 0, activeResearch: 0 },
  operations: [],
  agents: [],
  activeResearch: [],
  pinnedRecords: [],
  actionItems: [],
  activity: [],
  lastConversation: null,
}

export default async function OverviewPage() {
  const initial = (await fetchInitial()) ?? EMPTY_OVERVIEW
  return <DashboardHome initial={initial} />
}
