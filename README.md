# DECS for Relentless

Decision-Embedded Context System — architectural decision tracking integrated with Relentless.

## What It Does

Claude automatically records architectural decisions at the end of each coding session and recalls them at the start of the next. Decisions are stored as Decision nodes in Relentless, organized inside DECS container nodes within your projects.

## API Key Model

DECS uses a **DECS-scoped API key** — a restricted key that can only access `decision` and `decs` node kinds. This is separate from (and more limited than) the buildspace's full API key.

Every Relentless buildspace has two API keys:

| Key                    | Scope                          | Purpose                     |
| ---------------------- | ------------------------------ | --------------------------- |
| **Buildspace API Key** | Full access to all node kinds  | General API use             |
| **DECS API Key**       | `decision` + `decs` nodes only | DECS hooks and integrations |

DECS hooks **must** use the DECS key, not the buildspace key. This ensures that shell hooks running on your machine cannot read or modify anything outside of decisions — principle of least privilege.

## Setup

### 1. Install hooks

```bash
./decs/install.sh
```

This copies hooks to `~/.claude/hooks/` and the init skill to `~/.claude/skills/`.

### 2. Create credentials file

Open your Relentless profile (sidebar → Settings). Under **DECS API Key**, copy the key. Then create `~/.claude/decs-config.json`:

```json
{
  "relentlessApiKey": "rlnt_your_DECS_key_here",
  "relentlessUrl": "https://www.relentless.build",
  "buildspaceId": "your-buildspace-id"
}
```

**Important**: Use the **DECS API Key**, not the Buildspace API Key. The DECS key is restricted to decision and DECS nodes only — this is by design. Using the full buildspace key will work but violates the principle of least privilege.

Your Buildspace ID is the UUID in the URL bar when logged in (e.g. `/buildspace/019c2f...`).

### 3. Create a DECS node in Relentless

Open Relentless. Use Quick Capture (`Cmd+N`) and select **DECS**. Enter your project name. Place it inside a project node.

### 4. Connect to your repo

Copy the DECS node ID by clicking the `DECS` kind tag in the top-left of the node. Then either:

**Option A** — Run the skill in Claude Code:

```
/init-decs-project <paste-decs-id>
```

**Option B** — Just tell Claude:

```
Track DECS decisions for this repo in <paste-decs-id>
```

Both create a `.decs.json` file in your repo root. Commit this file so teammates share the same setup.

## How It Works

Three hooks run automatically:

- **SessionStart** (`get-decisions.sh`): Fetches decisions from Relentless, injects as context
- **UserPromptSubmit** (`decs-context.sh`): Re-injects decisions when "decision" or "decs" is mentioned (5-min cache)
- **Stop** (`decs-stop.sh`): Prompts Claude to document any new decisions before ending

## Decision Format

Each Decision node has four fields:

- **What**: Clear statement of the decision
- **Why**: Reasoning and alternatives considered
- **Purpose**: What outcome this serves
- **Constraints**: What this enables or limits for future work

## Key Decisions

Mark foundational choices as "Key Decision" — they are always injected into every session. Recent non-key decisions are limited to the 10 most recent.

## Upgrading

If you installed DECS before the DECS key model was introduced (before Feb 2026), run:

```
/decs-upgrade
```

This migrates your config from the old unscoped API key to the new DECS-scoped key.
