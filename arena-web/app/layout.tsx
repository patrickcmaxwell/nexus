import type { Metadata } from "next"
import "./globals.css"

export const metadata: Metadata = {
  title: "Arena — Nexus's executor",
  description: "The executor that takes Eve's tool calls and turns them into real-world action.",
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body>{children}</body>
    </html>
  )
}
