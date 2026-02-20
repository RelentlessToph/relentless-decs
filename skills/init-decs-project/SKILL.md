---
name: init-decs-project
description: Connect a DECS node to this repository. Use when setting up architectural decision tracking, enabling DECS, or when user says "init decs", "set up decision tracking", "track DECS decisions", or "configure DECS for this project". Links an existing DECS node in Relentless to this repo via .decs.json.
disable-model-invocation: true
argument-hint: <decs-node-id>
allowed-tools: Bash, Write, Read
---

# Understanding DECS Before You Begin

**Read this section carefully.** You're not just running config commands—you're onboarding a project to a decision tracking philosophy. Understanding WHY matters.

## The Fitted Sheet Problem

AI coding sessions are stateless. Each new session starts fresh with no memory of prior architectural commitments. This creates a pattern:

1. Session A decides "we'll use sync architecture for simplicity"
2. Session B, unaware, introduces async patterns "for better performance"
3. Session C tries to add a feature and finds contradictory patterns everywhere
4. Nobody remembers why either decision was made

It's like folding a fitted sheet—you fix one corner and another pops out. In software, this is called **architecture drift**: the gradual accumulation of decisions that contradict each other because no one can see the full picture.

## What DECS Actually Is

DECS (Decision-Embedded Context System) solves this by making prior decisions visible to every session:

- **Storage**: Decisions live in Relentless as Decision nodes inside a DECS container node (which lives inside a project node)
- **Injection**: A SessionStart hook queries the Relentless API and shows prior decisions as context
- **Coherence**: Claude naturally catches contradictions because it can SEE the history

It's not bureaucracy. It's not heavyweight process. It's a simple feedback loop: decisions go in, context comes out, coherence emerges.

## The Philosophy

**Decisions have trajectory.** Every architectural choice enables some future decisions and constrains others. When you choose REST over GraphQL, you're not just picking a protocol—you're shaping what's easy and hard for the next year.

**Ask "what outcome does this serve?"** Before documenting a decision, force yourself to articulate the PURPOSE. Not "we chose Postgres"—but "we chose Postgres because we need ACID transactions for financial data integrity."

**Three types of decisions:**

- **Problem Fix**: Dissolving or resolving an existing issue. Something's broken, we're fixing it.
- **Improvement**: Enhancing existing functionality. It works, we're making it better.
- **Redesign**: Fundamental rethinking. We're changing the approach entirely.

These labels help future sessions understand the NATURE of a decision, not just its content.

**Document the WHY, not just the WHAT.** Code shows what you did. Tests show what should happen. Decisions explain WHY you chose this path over alternatives.

## How It Works Technically

```
Relentless hierarchy:

  Project Node (e.g. "My App")
  └── "My App - Decisions" (kind: decs)     ← relentlessSpaceId in .decs.json
      ├── Decision 1
      ├── Decision 2
      └── ...

.decs.json (in repo root)          ~/.claude/hooks/get-decisions.sh
        │                                      │
        │ contains relentlessSpaceId           │ runs at session start
        │                                      │
        └──────────────┬───────────────────────┘
                       │
                       ▼
              Relentless API query
              (GET /api/nodes?parentId=SPACE_ID&kind=decision)
                       │
                       ▼
              Context injected into session
              "Prior Architectural Decisions: ..."
```

The `.decs.json` file maps THIS repo to a DECS node inside a Relentless project. The hook script reads it, queries Relentless for decision nodes, and injects them. Claude sees the history. Contradictions become visible.

## API Key: DECS-Scoped Key

DECS hooks use a **DECS-scoped API key** — a restricted key that can only access `decision` and `decs` node kinds. This is separate from the buildspace's full API key. Every buildspace automatically has a DECS key.

**Why a restricted key?** Shell hooks run on the user's machine with the API key in a JSON file. Restricting the key to decisions-only means even if the key leaks, it cannot read or modify anything outside of decisions. Principle of least privilege.

The key is stored in `~/.claude/decs-config.json` under the `relentlessApiKey` field.

## How to Use DECS Day-to-Day

### When to Create a Decision

Create a decision when you're making a choice that:

- **Affects architecture** — database choice, API design, sync vs async, monolith vs microservices
- **Will constrain future work** — "we're standardizing on React" means future UI work uses React
- **Has alternatives you considered** — if there was no real choice, it's not a decision
- **Would confuse a future session** — if you'd have to explain "why did we do it this way?", document it

**Don't document**: routine implementation details, obvious choices, things that can easily change.

### How Decisions Are Created

Decisions are recorded **automatically by Claude**:

1. At session end, the Stop hook prompts Claude to review the session for architectural decisions
2. Claude creates Decision nodes via the Relentless API — no manual work required
3. Key decisions (foundational, load-bearing choices) are flagged automatically

You can also create decisions manually in the Relentless UI or via the DECS node's "Add Decision" button.

### How Decisions Appear

Every new Claude session in this repo automatically sees prior decisions via the SessionStart hook. The context is injected before you even start typing — no action needed.

### Updating Decisions

Decisions can evolve:

- **Superseded**: Create a new decision that references and replaces the old one
- **Refined**: Edit the existing decision to clarify
- **Reversed**: Create a new decision explaining why you're going a different direction

---

# Connect DECS Node to This Repository

Now that you understand the philosophy, here's the execution.

## Current Context

- **Working directory**: !`pwd`
- **Git remote** (if available): !`git remote get-url origin 2>/dev/null || echo "not a git repo"`
- **Directory name**: !`basename "$(pwd)"`

## What This Does

Connects an existing DECS node in Relentless to this repository by writing `.decs.json`.

**Usage:** `/init-decs-project <decs-node-id>`

- `decs-node-id` (required): The UUID of the DECS node in Relentless. Users create this node in the Relentless UI first (Quick Capture → DECS), then copy the ID by clicking the kind tag.

**What it creates:**

- `.decs.json` in the repo root (or app directory for monorepos) pointing to the DECS node

## Relentless API Config

Credentials are stored in `~/.claude/decs-config.json`. Read values from there:

```bash
DECS_CONFIG="$HOME/.claude/decs-config.json"
API_KEY=$(jq -r '.relentlessApiKey' "$DECS_CONFIG")
BASE_URL=$(jq -r '.relentlessUrl' "$DECS_CONFIG")
BUILDSPACE_ID=$(jq -r '.buildspaceId' "$DECS_CONFIG")
```

**Note**: The `relentlessApiKey` field should contain a **DECS-scoped API key** (restricted to decision + decs node kinds), not the full buildspace key. If the user hasn't set this up yet, see Prerequisites below.

## Steps

### 1. Check Prerequisites

First verify `~/.claude/decs-config.json` exists. If not, tell the user:

> I need your Relentless credentials to continue. Create `~/.claude/decs-config.json` with:
>
> ```json
> {
>   "relentlessApiKey": "rlnt_...",
>   "relentlessUrl": "https://www.relentless.build",
>   "buildspaceId": "your-buildspace-id"
> }
> ```
>
> Open your Relentless profile (sidebar → Settings) and find the **DECS API Key** section. Copy that key — not the Buildspace API Key. The DECS key is restricted to decision and DECS nodes only, which is what the hooks need. Your buildspace ID is the UUID in the URL bar.

### 2. Parse Arguments

The first argument must be a UUID (the DECS node ID).

**If no arguments were provided, STOP and ask the user for the DECS node ID.** Explain: "I need the ID of your DECS node in Relentless. Open your DECS node, click the colored `DECS` tag in the top-left to copy its UUID, then run `/init-decs-project <that-id>`." Do NOT guess or proceed without it.

```bash
DECS_NODE_ID="<first argument — must be a UUID>"
```

### 3. Verify DECS Node Exists

```bash
curl -s "${BASE_URL}/api/nodes/${DECS_NODE_ID}?buildspaceId=${BUILDSPACE_ID}" \
  -H "Authorization: Bearer ${API_KEY}"
```

Verify:

- The response contains a valid node
- The node's `kind` is `"decs"` — if not, warn the user they may have provided the wrong ID

### 4. Create .decs.json

Write to the repo root (or the current app directory for monorepos):

```json
{
  "relentlessSpaceId": "DECS_NODE_ID"
}
```

For monorepos: if the current directory is inside a subdirectory (e.g., `apps/web/`), write `.decs.json` there instead of the repo root. This enables layered discovery — app-specific decisions override shared ones.

### 5. Optionally Update DECS Node Details

If the DECS node's content is mostly empty, offer to fill in details by PATCHing the node:

```bash
curl -s -X PATCH "${BASE_URL}/api/nodes/${DECS_NODE_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "content": {
      "projectName": "...",
      "repoUrl": "...",
      "appPath": "...",
      "techStack": "...",
      "description": "...",
      "branchingProcedure": "...",
      "testingProcedure": "..."
    }
  }'
```

Infer what you can from the codebase (package.json, framework, directory structure). Ask the user for anything you can't determine.

### 6. Verify

Run the hook to confirm decisions are being fetched:

```bash
~/.claude/hooks/get-decisions.sh
```

### Report Success

Tell the user:

- `.decs.json` created at `<path>`
- DECS node verified in Relentless
- How decisions work (automatic at session end, visible at session start)
- Remind them to commit `.decs.json` so teammates share the configuration

## Decision Format

Each decision node has four structured fields:

- **What**: Clear statement of the architectural decision
- **Why**: Reasoning—what problem does this solve? What alternatives were considered?
- **Purpose**: What outcome or goal this decision serves
- **Constraints**: What future decisions this enables or limits

## Key Decisions

Toggle the "Key Decision" star in the DecisionView for foundational choices that all future sessions must see. Use sparingly—only for load-bearing architectural choices. Key Decisions are always injected into every session regardless of age, while recent non-key decisions are limited to the 10 most recent.
