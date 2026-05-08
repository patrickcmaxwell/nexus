# maxnexus-public

The public face of `maxnexus.io`. Initially an ambient splash with a hidden passphrase doorway to the portal — designed to grow into a real marketing / mission / about site over time.

## What it is

- Standalone Next.js 16 app, deployed as its own Vercel project (`maxnexus-public`).
- Lives at the apex domain `maxnexus.io`.
- Today: ambient identity card. No nav, no info copy.
- Tomorrow: home for `/about`, `/manifesto`, public press, anything else outward-facing.
- The portal at `portal.maxnexus.io` is unaffected by anything that lands here.

## The hidden door

Type one of the secret words anywhere on the page (no input field — just start typing). Match → screen flashes briefly → redirect to the portal.

Defined in `app/Splash.tsx` → `PHRASES` map. Two kinds:
- **`open`** — match opens the door (redirects to portal). Currently: `lucy`, `lumen`.
- **`wink`** — match shows a small ack on screen but does nothing else. Currently: `vera`, `eve`, `noads`. Easter eggs for people in the know.

Add new phrases by editing the map. Keep the wink list shorter than the open list — wink phrases are flavor; open phrases are the real door.

Real auth (face / PIN) lives behind the redirect at `portal.maxnexus.io`. The passphrase here is mood + accidental-discovery prevention, not security.

## Mobile

Hidden hotspot in the bottom-right corner. Press-and-hold for 1.5s reveals a one-time text input. Same phrases work.

## Local dev

```bash
cd maxnexus-public
pnpm install
pnpm dev          # http://localhost:3002
```

## Deploy

```bash
cd maxnexus-public
vercel --prod --yes
```

## Env vars

- `NEXT_PUBLIC_PORTAL_URL` — where the door leads. Defaults to `https://portal.maxnexus.io`. Override only if the portal subdomain changes.

## Future

Replace the centered glyph + "M A X N E X U S" word with real branding when it lands. Add `/about`, `/manifesto`, or whatever marketing surfaces you want — the splash route at `/` stays as the doorway, secondary routes pick up the marketing job. Search engines are explicitly blocked via `robots: { index: false, follow: false }` in the layout — flip that off when you actually want indexing.
