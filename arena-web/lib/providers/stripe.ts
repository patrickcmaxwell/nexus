import {
  Provider, PaymentInput, PaymentResult,
  TestConnectionInput, TestConnectionResult,
} from "./index"

// Stripe provider — payment routing.
//
// Stripe Connect is the right primitive for the "split a total across
// multiple recipients" use case (Eve's arena_payment_route tool). Each
// recipient needs to be a Connect account on the platform; Eve creates
// transfers per split.
//
// This shipping ship-of-Theseus pass implements:
//   - Connect form (secret key, default destination)
//   - testConnection (probes /v1/account)
//   - routePayment as a STUB that validates splits + returns mocked:true
//
// Wiring real transfers requires:
//   1. Patrick's Stripe account approved for Connect
//   2. A way to map split.to (e.g. an email or name) to a Connect account_id
//   3. Idempotency keys so retries don't double-pay
// Those are product decisions, not just implementation. The current shape
// gets the audit log + UI surface in place so the moment Patrick says "go"
// the swap is one method body.

const API_BASE = "https://api.stripe.com/v1"

export const stripe: Provider = {
  id: "stripe",
  name: "Stripe",
  description: "Route payments + splits Eve initiates. Connect-based — recipients live as Connect accounts.",
  icon: "credit-card",
  accent: "oklch(0.65 0.22 270)",  // Stripe purple

  connectFields: [
    {
      key: "secret_key",
      label: "Secret Key",
      placeholder: "sk_live_... or sk_test_...",
      helperText: "Restricted key recommended. Needs Charges + Transfers + Connect Read/Write.",
      required: true,
      secret: true,
      type: "password",
    },
    {
      key: "default_currency",
      label: "Default Currency",
      placeholder: "usd",
      helperText: "ISO 4217 lowercase. Used when Eve doesn't specify.",
      required: false,
      secret: false,
      type: "text",
    },
  ],

  async testConnection({ values }: TestConnectionInput): Promise<TestConnectionResult> {
    const key = values.secret_key
    if (!key) return { ok: false, detail: "Missing secret key" }
    if (!key.startsWith("sk_")) return { ok: false, detail: "Doesn't look like a Stripe secret key (sk_…)" }
    try {
      const res = await fetch(`${API_BASE}/account`, {
        headers: { Authorization: `Bearer ${key}` },
      })
      if (res.status === 401) return { ok: false, detail: "Key rejected" }
      if (!res.ok) return { ok: false, detail: `Stripe returned HTTP ${res.status}` }
      const account = await res.json() as { id?: string; business_profile?: { name?: string } }
      const name = account.business_profile?.name ?? account.id ?? "your account"
      const mode = key.startsWith("sk_test_") ? "TEST MODE" : "LIVE MODE"
      return { ok: true, detail: `Connected to ${name} · ${mode}` }
    } catch (err) {
      return { ok: false, detail: err instanceof Error ? err.message : "Network error" }
    }
  },

  async routePayment({ connection, totalAmount, currency, splits }: PaymentInput): Promise<PaymentResult> {
    // Always mock for now — see header comment. The validation layer in
    // /api/payment/route catches mismatched-sum splits before getting here,
    // so by the time we're called the math is sound.
    const recipients = splits.length
    return {
      routedAmount: totalAmount,
      recipients,
      mocked: true,
      detail: connection.credentials.secret_key
        ? `Stripe Connect not yet wired — ${recipients} transfers would be issued for ${currency} ${totalAmount.toFixed(2)}`
        : `No Stripe key — ${recipients} transfers mocked for ${currency} ${totalAmount.toFixed(2)}`,
    }
  },
}
