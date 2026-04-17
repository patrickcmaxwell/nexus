# Arena

The executor layer of Nexus. **Eve thinks. Arena does.**

## Purpose

Arena is the middleware that connects Eve to the real world — ClickUp, payments, Google, and any other external service.

## Setup

```bash
cd arena
npm install
npm run dev
```

Runs on port 3001 by default.

## Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/health` | Check Arena is running |
| POST | `/task/create` | Create a ClickUp task |
| POST | `/task/update` | Update a ClickUp task |
| POST | `/payment/route` | Route and split a payment |
| POST | `/sync/push` | Push memory package to Supabase for iPhone |

## Example: Eve tells Arena to create a task

```python
# From desktop/main.py
call_arena("/task/create", {
    "title": "New client proposal",
    "assignee": "patrick",
    "due": "2026-04-24"
})
```

## Rules

- Only act when Eve explicitly instructs
- Log every action (to console now, Supabase later)
- Never make financial decisions without explicit instruction
- All actions reversible where possible
