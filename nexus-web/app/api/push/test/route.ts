// POST /api/push/test
//
// Fires a single test notification to every device the caller has
// registered. Lets the user verify the round-trip without needing an
// agent run or schedule firing to happen first.
//
// Returns the dispatch breakdown so the UI can show "sent N · skipped M
// · failed K" with concrete numbers, including the skip reason
// (APNS_NOT_CONFIGURED is the most common one).
import { NextResponse } from "next/server"
import { getActiveHuman } from "@/lib/auth/session"
import { sendPush } from "@/lib/push/dispatch"

export async function POST() {
  const me = await getActiveHuman()
  if (!me) return NextResponse.json({ error: "Not authenticated" }, { status: 401 })

  const result = await sendPush(me.humanId, "agent.done", {
    title: "Nexus push test",
    body: "If you see this, the push pipeline is wired end-to-end.",
    link: "nexus://dashboard",
    extra: { test: true },
  })
  return NextResponse.json(result)
}
