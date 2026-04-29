export default function SignUpSuccessPage() {
  return (
    <main className="min-h-screen bg-background flex items-center justify-center scan-line px-4">
      <div className="w-full max-w-md text-center flex flex-col items-center gap-6">
        <div className="w-20 h-20 hud-border hud-glow-gold rounded-sm flex items-center justify-center">
          <span className="text-hud-gold font-bold text-3xl animate-pulse-glow" style={{ fontFamily: "var(--font-orbitron)" }}>✓</span>
        </div>
        <h1 className="text-hud-gold text-xl font-bold tracking-widest" style={{ fontFamily: "var(--font-orbitron)" }}>
          CLEARANCE REQUESTED
        </h1>
        <div className="hud-border p-6 bg-card w-full">
          <p className="font-mono text-sm text-muted-foreground leading-relaxed">
            Your registration has been submitted to Maxwell Nexus security. Please check your email to confirm your identity before accessing the system.
          </p>
        </div>
        <a
          href="/auth/login"
          className="px-8 py-3 hud-border text-hud-red font-mono text-sm tracking-widest hover:bg-[oklch(0.55_0.22_25/0.15)] transition-all duration-200"
          style={{ fontFamily: "var(--font-orbitron)" }}
        >
          RETURN TO LOGIN
        </a>
      </div>
    </main>
  )
}
