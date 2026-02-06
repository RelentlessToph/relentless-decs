---
name: init-decs-project
description: Initialize DECS decision tracking for a repository. Use when setting up architectural decision tracking, enabling DECS, or when user says "init decs", "set up decision tracking", or "configure DECS for this project". Creates a Decisions space inside a Relentless project node.
disable-model-invocation: true
argument-hint: <project-node-id> [project-name]
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

- **Storage**: Decisions live in Relentless as Decision nodes inside a Decisions space (which lives inside a project node)
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
  └── "My App - Decisions" (collection)    ← relentlessSpaceId in .decs.json
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
              (GET /api/nodes?parentId=SPACE_ID&kind=decision&buildspaceId=BUILDSPACE_ID)
                       │
                       ▼
              Context injected into session
              "Prior Architectural Decisions: ..."
```

The `.decs.json` file maps THIS repo to a Decisions space inside a Relentless project node. The hook script reads it, queries Relentless for decision nodes, and injects them. Claude sees the history. Contradictions become visible.

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

You can also create decisions manually in the Relentless UI or via `/decision` in the command bar if needed.

### How Decisions Appear

Every new Claude session in this repo automatically sees prior decisions via the SessionStart hook. The context is injected before you even start typing — no action needed.

### Updating Decisions

Decisions can evolve:

- **Superseded**: Create a new decision that references and replaces the old one
- **Refined**: Edit the existing decision to clarify
- **Reversed**: Create a new decision explaining why you're going a different direction

---

# Initialize DECS for Current Repository

Now that you understand the philosophy, here's the execution.

## Current Context

- **Working directory**: !`pwd`
- **Git remote** (if available): !`git remote get-url origin 2>/dev/null || echo "not a git repo"`
- **Directory name**: !`basename "$(pwd)"`

## What This Does

Creates a "PROJECT_NAME - Decisions" collection inside an existing Relentless project node, then writes `.decs.json` to the repo root.

**Usage:** `/init-decs-project <project-node-id> [project-name]`

- `project-node-id` (required): The UUID of the project node in Relentless. Users can copy this by clicking the kind tag (e.g. `PROJECT`) on the node.
- `project-name` (optional): Name for the Decisions space. Defaults to directory name.

**What it creates:**

- A "PROJECT_NAME - Decisions" collection node inside the project node
- A bootstrap decision to confirm the setup works
- `.decs.json` in the repo root pointing to the Decisions space

## Relentless API Config

Credentials are stored in `~/.claude/decs-config.json`. Read values from there:

```bash
DECS_CONFIG="$HOME/.claude/decs-config.json"
API_KEY=$(jq -r '.relentlessApiKey' "$DECS_CONFIG")
BASE_URL=$(jq -r '.relentlessUrl' "$DECS_CONFIG")
BUILDSPACE_ID=$(jq -r '.buildspaceId' "$DECS_CONFIG")
```

## Steps

### 1. Parse Arguments

The first argument must be a UUID (the project node ID). The second argument (if present) is the project name.

**If no arguments were provided, STOP and ask the user for the project node ID.** Explain: "I need the ID of your project node in Relentless. Open your project, click the colored kind tag in the top-left (e.g. `PROJECT`) to copy its UUID, then run `/init-decs-project <that-id>`." Do NOT guess, create a new project, or proceed without it.

```bash
# Parse: first arg is project node UUID, rest is optional project name
PROJECT_NODE_ID="<first argument — must be a UUID>"
PROJECT_NAME="<second argument, or directory name from context above>"
```

### 2. Verify Project Node Exists

```bash
curl -s "${BASE_URL}/api/nodes/${PROJECT_NODE_ID}?buildspaceId=${BUILDSPACE_ID}" \
  -H "Authorization: Bearer ${API_KEY}"
```

If it returns an error or the node doesn't exist, tell the user and stop. The project node must already exist in Relentless.

### 3. Create Decisions Space Inside Project

```bash
curl -s -X POST "${BASE_URL}/api/nodes?buildspaceId=${BUILDSPACE_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "collection",
    "title": "PROJECT_NAME - Decisions",
    "parentId": "PROJECT_NODE_ID"
  }'
```

Extract the `id` from the JSON response — this is the Decisions space ID.

---

### Create .decs.json

Write to repo root with the space ID (from either mode):

```json
{
  "relentlessSpaceId": "SPACE_ID"
}
```

### Create Bootstrap Decision

Create the first decision to confirm everything works:

```bash
curl -s -X POST "${BASE_URL}/api/nodes?buildspaceId=${BUILDSPACE_ID}" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "decision",
    "title": "Use DECS for architectural decision tracking",
    "content": {
      "what": "We adopted DECS (Decision-Embedded Context System) for tracking architectural decisions in this project.",
      "why": "AI sessions are stateless. Without explicit decision tracking, successive sessions introduce contradictory patterns. DECS creates a feedback loop: decisions go in, context comes out, coherence emerges.",
      "purpose": "Maintain architectural coherence across AI coding sessions and preserve the reasoning behind choices.",
      "constraints": "All significant architectural choices should be documented as decisions. Future sessions will see these automatically via the SessionStart hook.",
      "isKeyDecision": true
    },
    "parentId": "SPACE_ID"
  }'
```

### Verify

Run the hook to confirm decisions are being fetched:

```bash
~/.claude/hooks/get-decisions.sh
```

### Report Success

Tell the user:

- Decisions space created in Relentless
- Location of `.decs.json`
- How to create decisions (in Relentless UI or via `/decision` command)
- That the bootstrap decision has been created

## Decision Format

Each decision node has four structured fields:

- **What**: Clear statement of the architectural decision
- **Why**: Reasoning—what problem does this solve? What alternatives were considered?
- **Purpose**: What outcome or goal this decision serves
- **Constraints**: What future decisions this enables or limits

## Key Decisions

Toggle the "Key Decision" star in the DecisionView for foundational choices that all future sessions must see. Use sparingly—only for load-bearing architectural choices. Key Decisions are always injected into every session regardless of age, while recent non-key decisions are limited to the 10 most recent.
