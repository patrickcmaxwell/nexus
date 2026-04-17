# Memory

This folder contains Eve's long-term memory and personality files.
**This is the most important folder in the entire system.**

## Files

| File | Who sees it | Purpose |
|------|------------|---------|
| `eve-base.md` | Everyone | Core personality — always loaded |
| `eve-private.md` | Patrick only | Full personal memory, thinking style, past conversations |
| `eve-shared.md` | Trusted users | Project context only, no private memories |

## How it loads

```
Patrick logs in  →  eve-base.md + eve-private.md
Anyone else      →  eve-base.md + eve-shared.md
```

## Critical Rules

- These files are sacred — never delete or overwrite carelessly
- Eve must read the appropriate files at the start of every session
- Add important new context to eve-private.md as the relationship grows
- These files are the main difference between a generic AI and *your* Eve
