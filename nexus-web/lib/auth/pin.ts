// PIN hashing + verification helpers.
//
// Current scheme: SHA256 of the PIN (no salt). Known-weak for a 4-digit
// PIN — fully precomputable (10K hashes). The active mitigation is rate
// limiting on auth endpoints; long-term fix is to migrate to bcrypt /
// argon2id with a per-user salt and rehash on next login.
//
// Always compare hashes with `timingSafePinEqual` — direct `===`/`!==`
// short-circuits on first byte mismatch and leaks correct-prefix info.

import crypto from "crypto"

export function hashPin(pin: string): string {
  return crypto.createHash("sha256").update(pin).digest("hex")
}

/**
 * Constant-time hex-string comparison. Length check up front so
 * `Buffer.from` never throws on differently-sized inputs.
 */
export function timingSafePinEqual(a: string | null | undefined, b: string | null | undefined): boolean {
  if (!a || !b || a.length !== b.length) return false
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))
}
