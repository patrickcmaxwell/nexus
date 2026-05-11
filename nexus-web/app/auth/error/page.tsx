import Link from "next/link"

export const dynamic = "force-dynamic"

// Recovery / help screen. Linked from "I can't get in" on the auth gate +
// hit directly with ?code=<reason> when an auth attempt knows what failed.
// Each code lights up its own contextual help. Users see WHAT to try next
// instead of a brick wall.
export default async function AuthErrorPage({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>
}) {
  const { code } = await searchParams
  const advice = adviceFor(code ?? "help")

  return (
    <main className="min-h-screen bg-background flex items-center justify-center px-4 py-10">
      <div className="w-full max-w-md flex flex-col items-center gap-6">
        <div
          className="w-16 h-16 flex items-center justify-center"
          style={{
            border: `1px solid ${advice.color}`,
            background: `${advice.color}10`,
            borderRadius: 4,
          }}
        >
          <span className="text-3xl font-bold" style={{ color: advice.color }}>
            {advice.symbol}
          </span>
        </div>

        <div className="text-center">
          <p
            className="text-xs font-medium mb-2"
            style={{ color: advice.color }}
          >
            {advice.headline}
          </p>
          <h1 className="text-2xl font-bold text-foreground">{advice.title}</h1>
        </div>

        <div className="w-full p-5 bg-card/40 border border-border rounded-sm">
          <p className="text-sm text-muted-foreground leading-relaxed">{advice.body}</p>
          {advice.steps.length > 0 && (
            <ol className="mt-4 space-y-2 text-sm text-muted-foreground">
              {advice.steps.map((step, i) => (
                <li key={i} className="flex gap-2">
                  <span
                    className="text-xs font-semibold mt-0.5"
                    style={{ color: "var(--primary)" }}
                  >
                    {String(i + 1).padStart(2, "0")}.
                  </span>
                  <span>{step}</span>
                </li>
              ))}
            </ol>
          )}
        </div>

        <div className="flex flex-col w-full gap-2">
          <Link
            href="/"
            className="px-6 py-3 text-xs font-medium text-center"
            style={{
              color: "var(--primary)",
              background: "oklch(0.75 0.18 200 / 0.1)",
              border: "1px solid oklch(0.75 0.18 200 / 0.5)",
            }}
          >
            Back to Sign In
          </Link>
          <a
            href="mailto:patrick@maxnexus.io?subject=Nexus%20access%20help"
            className="px-6 py-3 text-xs font-medium text-center text-muted-foreground/55 hover:text-muted-foreground"
          >
            Get access help →
          </a>
        </div>
      </div>
    </main>
  )
}

type Advice = {
  symbol: string
  color: string
  headline: string
  title: string
  body: string
  steps: string[]
}

function adviceFor(code: string): Advice {
  switch (code) {
    case "blocked":
    case "IP_BLOCKED":
      return {
        symbol: "✕",
        color: "var(--nexus-danger)",
        headline: "IP Blocked",
        title: "Too many attempts from your network.",
        body:
          "You've tried to sign in too many times in a short window. Your IP is on a temporary blocklist. This usually clears in 15-30 minutes.",
        steps: [
          "Wait 15-30 minutes and try again.",
          "If you're sure you have the right credentials, contact the owner to lift the block manually.",
          "Avoid retrying repeatedly — each attempt extends the cooldown.",
        ],
      }
    case "UNKNOWN_EMAIL":
      return {
        symbol: "?",
        color: "oklch(0.85 0.16 90)",
        headline: "Email not recognized",
        title: "We don't have an account with that email.",
        body:
          "The address you typed isn't on the team. This usually means you mistyped it, or you haven't been invited yet.",
        steps: [
          "Double-check the address — small typos are the usual culprit.",
          "If you're expecting an invite, search your inbox (and spam folder) for an email from Nexus.",
          "Contact the owner to confirm whether you've been added.",
        ],
      }
    case "WRONG_PIN":
      return {
        symbol: "⌧",
        color: "var(--nexus-danger)",
        headline: "PIN incorrect",
        title: "That PIN doesn't match.",
        body:
          "Your email is recognized but the PIN you typed isn't right. After several wrong attempts, your IP gets temporarily blocked.",
        steps: [
          "Try again — make sure you're using the PIN you set, not your master passphrase.",
          "If you've forgotten your PIN, the owner can reset it from /dashboard/humans.",
          "If you set up multiple PINs across accounts, double-check which one belongs to this email.",
        ],
      }
    case "INVITE_NOT_ACCEPTED":
      return {
        symbol: "✉",
        color: "oklch(0.78 0.18 265)",
        headline: "Invite not completed",
        title: "Your account is invited but not set up yet.",
        body:
          "We sent you an invite email with a setup link. You need to follow it to choose a PIN and (optionally) enroll your face before you can sign in.",
        steps: [
          "Check your inbox + spam folder for an email from Nexus.",
          "Click the link, set your PIN, finish the wizard.",
          "If the link expired, ask the owner to resend the invite.",
        ],
      }
    case "ACCOUNT_LOCKED":
      return {
        symbol: "🔒",
        color: "var(--nexus-danger)",
        headline: "Account locked",
        title: "This account has been locked by an admin.",
        body:
          "Locked accounts can't sign in until an admin lifts the lock. This usually means the owner intentionally disabled access.",
        steps: [
          "Contact the owner to unlock the account.",
          "Check whether someone has been informed of why the lock was applied.",
        ],
      }
    case "help":
    default:
      return {
        symbol: "?",
        color: "oklch(0.78 0.18 200)",
        headline: "Trouble signing in",
        title: "Let's figure out where it's stuck.",
        body:
          "If sign-in isn't working, walk through these in order. Most issues are one of: wrong email, wrong PIN, blocked IP, or an invite that was never finished.",
        steps: [
          "Confirm the email exactly matches what you were invited with.",
          "If you forget your PIN, ask the owner to reset it.",
          "If you've just been invited, look for the setup email.",
          "If you've tried too many times, wait 15-30 minutes for the IP block to clear.",
        ],
      }
  }
}
