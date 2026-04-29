# nexus-web
Your existing Next.js + Node.js codebase goes here.
Move or clone your Bolt.dev project into this folder.

# nexus-teams aka humans

# Humans — The People Layer in Nexus

> Everyone in Nexus is a Human. Not a user. Not a team member. A Human.

---

## The Problem We're Solving

Right now when you invite someone (like Merlin), they see everything — all your chats, private data, personal memory. That's wrong. We need a permission system that:

- Keeps your private stuff private
- Lets you share specific things intentionally
- Lets Humans form their own groups/teams
- Shows who's in the system and what they've shared publicly

---

## Core Concepts

### Humans
Anyone in the Nexus system is a Human. Not a "user" or "team member." Humans can:
- Have their own private agents, operations, data
- Share specific data with other Humans or groups
- See other Humans on the Nexus map
- Form or join groups

### Groups
Humans can create or join groups (could be called crews, teams, cells — TBD). A group has:
- Shared agents and operations
- Shared data sets
- Group-level permissions
- A group map showing all members

### Data Ownership
Every piece of data in Nexus has an owner and a visibility level:

| Level | Who Sees It |
|-------|-------------|
| `private` | Only you |
| `shared` | Specific Humans or groups you choose |
| `group` | Everyone in your group(s) |
| `public` | All Humans in Nexus |

---

## Permission Levels for Humans You Invite

When you invite a Human, you assign them an access level. They should NOT see your private data by default.

### Access Levels

| Level | What They Can See / Do |
|-------|------------------------|
| `observer` | Public data only. Can see the Nexus map and public operations. Read-only. |
| `collaborator` | Shared data you explicitly assign. Can work on shared operations and agents. |
| `operator` | Can create their own agents and operations inside Nexus. Full access to shared data. |
| `admin` | Full access except your private memory (eve-private.md stays sacred always). |

### What's ALWAYS Private (never accessible to anyone)
- `eve-private.md` — your personal memory
- Your private conversations with Eve/Lumen
- Any data you explicitly mark `private`
- Your financial data in Arena (unless explicitly shared)

---

## Nexus Map

The Nexus map shows the ecosystem of Humans in your system. Each Human node displays:
- Their name / handle
- Their role / access level
- Public agents they've created
- Public operations they're running
- Public data sets they've made available
- Groups they belong to

Clicking a Human on the map shows their public profile and shared data. Private data is never visible on the map.

---

## What Needs to Be Built

### Database (Supabase)

```sql
-- Humans table (replaces raw auth users)
humans (
  id uuid primary key,
  auth_id uuid references auth.users,
  handle text unique,         -- @merlin, @patrick
  display_name text,
  avatar_url text,
  role text default 'observer',
  created_at timestamp,
  is_owner boolean default false  -- Patrick is the system owner
)

-- Groups
groups (
  id uuid primary key,
  name text,
  description text,
  created_by uuid references humans,
  created_at timestamp
)

-- Group membership
group_members (
  group_id uuid references groups,
  human_id uuid references humans,
  role text default 'member',  -- member | moderator | owner
  joined_at timestamp
)

-- Data visibility
data_permissions (
  id uuid primary key,
  resource_type text,   -- agent | operation | directive | protocol | dataset
  resource_id uuid,
  owner_id uuid references humans,
  visibility text,      -- private | shared | group | public
  shared_with uuid[],   -- specific human IDs if visibility = shared
  group_id uuid         -- group ID if visibility = group
)
```

### Invite Flow (Fix the current broken one)

1. Patrick generates an invite link with a pre-set access level
2. Human signs up via invite link
3. They land in Nexus with ONLY what their access level allows
4. Patrick can adjust their level at any time from the Humans panel
5. Humans can see their own level and what they have access to

### UI Components Needed

**Humans Panel (slides in on desktop/web)**
- List of all Humans in the system
- Their access level badge
- Quick toggle to change their level
- Invite new Human button (with level selector before sending)

**Human Profile Card**
- Shows on Nexus map
- Public agents, operations, shared data
- Groups they belong to

**My Permissions View**
- Every Human can see exactly what they have access to
- No confusion about what's visible

**Group Management**
- Create a group
- Invite Humans to a group
- Set group-level shared data

---

## Data Separation Rules

These rules must be enforced at the database level (Supabase RLS), not just the UI:

1. **Private data** → RLS policy: only owner can read/write
2. **Shared data** → RLS policy: owner + specific human IDs in `shared_with`
3. **Group data** → RLS policy: owner + all members of `group_id`
4. **Public data** → RLS policy: any authenticated Human can read, only owner can write
5. **eve-private.md** → Never stored in Supabase. Local only. Never synced.

---

## What to Build First (Phase 1)

1. Fix the invite flow — access level selector before inviting
2. Supabase RLS policies for data isolation
3. Humans table + migrate existing users
4. Humans panel in the web UI
5. Basic Nexus map showing Humans and their public data

## Phase 2

6. Groups — create, join, manage
7. Data permission controls on each resource
8. Human profile cards on the map
9. Desktop Lumen integration — Humans visible from voice commands

---

## Claude Code Prompt (run this next)

```
We are adding a Humans system to Nexus. Read this file first: HUMANS_README.md

Here is what to build in Phase 1:

1. Create a Supabase migration file at nexus-web/supabase/migrations/001_humans.sql
   - humans table (id, auth_id, handle, display_name, avatar_url, role, created_at, is_owner)
   - groups table
   - group_members table  
   - data_permissions table
   - RLS policies: private data = owner only, shared = owner + shared_with array, group = group members, public = all authenticated

2. Fix the invite flow in nexus-web:
   - Before sending invite, show a modal with access level selector (observer / collaborator / operator / admin)
   - Store the intended role in the invite record
   - On signup via invite, assign that role immediately
   - New humans should see ZERO of Patrick's private data by default

3. Create a Humans panel component:
   - List all humans in the system
   - Show their handle, display name, access level badge
   - Dropdown to change their access level
   - Invite button that opens the level selector first

4. Update .cursor/rules to include the Humans system rules

Do NOT let any human see eve-private.md or Patrick's private conversations under any circumstances.
The system owner (is_owner = true) always has full access to everything except other humans' private data.
```

---

*Everyone in Nexus is a Human. Private by default. Shared by choice.*
