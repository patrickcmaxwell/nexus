"use client"

import { useRouter } from "next/navigation"
import { useEffect } from "react"

// Entry point is now / — redirect there
export default function LoginPage() {
  const router = useRouter()
  useEffect(() => { router.replace("/") }, [router])
  return null
}
