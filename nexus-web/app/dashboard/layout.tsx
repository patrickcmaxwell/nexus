import { cookies } from "next/headers"
import { redirect } from "next/navigation"
import DashboardSidebar from "@/components/dashboard/DashboardSidebar"
import FloatingEveWrapper from "@/components/dashboard/FloatingEveWrapper"
import SearchPalette from "@/components/search/SearchPalette"
import { getSessionMember } from "@/lib/operations/auth"

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get("nx_session")?.value

  if (!sessionId) {
    redirect("/")
  }

  // Get the current team member info for personalization
  const member = await getSessionMember()
  const displayName = member?.name || member?.email?.split("@")[0] || "User"
  const displayEmail = member?.email || ""
  const memberRole = member?.role || "observer"
  const memberAvatarUrl = member?.avatarUrl ?? null

  return (
    <div className="min-h-screen bg-background text-foreground">
      <DashboardSidebar
        userEmail={displayEmail}
        userName={displayName}
        userRole={memberRole}
        userAvatarUrl={memberAvatarUrl}
      />
      {/*
        Switch sidebar/mobile-nav handoff from md: (768px) to lg: (1024px).
        At md: width (iPad portrait, narrow desktop windows), the desktop
        sidebar reserved 288px of horizontal space but the chat surface
        ended up unusably narrow. Promoting to lg: gives tablets the
        mobile layout, which is the right experience until we have a
        proper compact-sidebar variant for that range.
      */}
      <main className="lg:ml-72 pb-20 lg:pb-0">
        {children}
      </main>
      <FloatingEveWrapper />
      {/* Cmd-K palette mounted globally so any dashboard page can search. */}
      <SearchPalette />
    </div>
  )
}
