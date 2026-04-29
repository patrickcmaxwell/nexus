"use client"

import Link from "next/link"
import { Briefcase, FileText, MessageSquare, Bot, Tag } from "lucide-react"
import { MENTION_TYPE_COLORS } from "@/lib/mentions/types"
import type { MentionType } from "@/lib/mentions/types"

// Inline chip used when rendering a mention inside a message. Clickable —
// each type routes to the most useful place for that entity:
//   operation    -> /dashboard/operations?op=<id>
//   record       -> /dashboard/operations?record=<id>  (opens drawer)
//   conversation -> /dashboard/maxwell?c=<id>
//   topic        -> /dashboard/maxwell?c=<convId>#topic-<id> — but we don't
//                   have the convId at render time, so just jump to the
//                   Maxwell index and let Eve pick up the topic on load.
//   agent        -> /dashboard/agents?agent=<id>
//
// Styling is shared across the live input and rendered messages so the same
// chip looks identical everywhere.

type Props = {
  type: MentionType
  id: string
  label: string
  // When used inline in a user-editable input, we don't want the chip to be
  // a Link (clicking would navigate away mid-compose). Pass `static` to
  // render a non-interactive span with the same styling.
  static?: boolean
}

const ICONS: Record<MentionType, React.ComponentType<{ size?: number }>> = {
  operation: Briefcase,
  record: FileText,
  conversation: MessageSquare,
  topic: Tag,
  agent: Bot,
}

function hrefFor(type: MentionType, id: string): string {
  switch (type) {
    case "operation":    return `/dashboard/operations?op=${id}`
    case "record":       return `/dashboard/operations?record=${id}`
    case "conversation": return `/dashboard/maxwell?c=${id}`
    case "topic":        return `/dashboard/maxwell`
    case "agent":        return `/dashboard/agents?agent=${id}`
  }
}

export default function MentionChip({ type, id, label, static: isStatic }: Props) {
  const Icon = ICONS[type]
  const colors = MENTION_TYPE_COLORS[type]
  const content = (
    <>
      <Icon size={10} />
      <span className="truncate max-w-[180px]">{label}</span>
    </>
  )
  const className = "inline-flex items-center gap-1 px-1.5 py-0.5 rounded font-medium align-baseline border leading-[1.3] text-[11.5px]"
  const style = { color: colors.fg, background: colors.bg, borderColor: colors.border }

  if (isStatic) {
    return <span className={className} style={style} contentEditable={false} data-mention-chip={`${type}:${id}`}>{content}</span>
  }
  return (
    <Link href={hrefFor(type, id)} className={className + " hover:brightness-125 transition-all no-underline"} style={style}>
      {content}
    </Link>
  )
}
