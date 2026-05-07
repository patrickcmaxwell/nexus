// Provider registry + abstract interface.
//
// Every external integration (ClickUp, Stripe, Notion, …) implements the
// `Provider` interface and registers in `ALL_PROVIDERS`. Adding a new one
// is a single file + one line in the registry.
//
// Eve's tool calls dispatch to providers via this registry; the user UI
// renders one card per registered provider with whatever config form the
// provider declares.

import { clickup } from "./clickup"
import { notion } from "./notion"
import { github } from "./github"
import { stripe } from "./stripe"
import { slack } from "./slack"

export type ProviderId = "clickup" | "stripe" | "notion" | "github" | "slack"

export type ConnectionRecord = {
  id: string
  userId: string
  provider: ProviderId
  label: string | null
  credentials: Record<string, string>   // provider-shaped payload (api_key, etc.)
  config: Record<string, string>        // non-secret settings
  status: "active" | "errored" | "disabled"
  lastUsedAt: string | null
  lastError: string | null
}

export type CreateTaskInput = {
  connection: ConnectionRecord
  title: string
  description?: string
  dueDate?: string
  priority?: "urgent" | "high" | "normal" | "low"
}

export type UpdateTaskInput = {
  connection: ConnectionRecord
  externalId: string                    // provider's own task id
  status?: string
  comment?: string
}

export type TaskResult = {
  externalId?: string                   // provider's id when created
  url?: string                          // direct link to the task
  mocked: boolean                       // true when the provider was unconfigured
  detail?: string
}

export type PaymentInput = {
  connection: ConnectionRecord
  totalAmount: number
  currency: string
  splits: Array<{ to: string; amount: number; note?: string }>
}

export type PaymentResult = {
  routedAmount: number
  recipients: number
  mocked: boolean
  detail?: string
}

export type SyncPushInput = {
  connection: ConnectionRecord
  payload: Record<string, unknown>
}

export type SyncResult = {
  ok: boolean
  mocked: boolean
  detail?: string
}

/// What a provider can do. Each method is optional so Stripe doesn't have
/// to implement createTask, ClickUp doesn't have to implement routePayment.
/// Eve's tool routing inspects which providers expose which methods.
export interface Provider {
  id: ProviderId
  name: string
  /** One-liner shown in the connections UI. */
  description: string
  /** Lucide icon name (rendered by UI). */
  icon: string
  /** Color tint used for the provider's card. */
  accent: string
  /** Form schema for the connect flow (see ConnectionField). */
  connectFields: ConnectionField[]

  createTask?(input: CreateTaskInput): Promise<TaskResult>
  updateTask?(input: UpdateTaskInput): Promise<TaskResult>
  routePayment?(input: PaymentInput): Promise<PaymentResult>
  syncPush?(input: SyncPushInput): Promise<SyncResult>

  /// Verify the supplied credentials before saving. Cheap probe (e.g.
  /// GET /me on the provider's API). Returns ok=true if the creds work,
  /// or a useful error string if not. Implementing this lights up the
  /// "Test" button in the connect form.
  testConnection?(input: TestConnectionInput): Promise<TestConnectionResult>
}

export type TestConnectionInput = {
  /** Form values the user has typed but not yet saved. */
  values: Record<string, string>
}

export type TestConnectionResult = {
  ok: boolean
  detail: string
}

export type ConnectionField = {
  key: string                           // stored in credentials or config under this key
  label: string
  placeholder?: string
  helperText?: string
  required: boolean
  secret: boolean                       // true → goes into `credentials`, false → `config`
  type: "text" | "password"
}

/// Registry. Add new providers here.
export const ALL_PROVIDERS: Provider[] = [
  clickup,
  notion,
  github,
  stripe,
  slack,
]

export function findProvider(id: string): Provider | null {
  return ALL_PROVIDERS.find((p) => p.id === id) ?? null
}
