"use client"

import { usePathname } from "next/navigation"
import FloatingEve from "./FloatingEve"

export default function FloatingEveWrapper() {
  const pathname = usePathname()
  // Hide on the full Eve page and the dashboard home — both have their own
  // primary Eve interface, and a second floating Eve would compete with them.
  if (pathname.startsWith("/dashboard/maxwell")) return null
  if (pathname === "/dashboard") return null
  return <FloatingEve />
}
