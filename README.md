# DECS for Relentless

Decision-Embedded Context System — Claude Code hooks for architectural decision tracking with [Relentless](https://relentless.build).

## What It Does

Claude automatically records architectural decisions at the end of each coding session and recalls them at the start of the next. Decisions are stored as Decision nodes in Relentless, organized in a Decisions space inside each project node.

## Prerequisites

- A [Relentless](https://relentless.build) account
- [Claude Code](https://claude.ai/code) CLI
- `jq` and `curl` installed

## Setup

### 1. Clone and install

```bash
git clone https://github.com/RelentlessToph/relentless-decs.git
cd relentless-decs
./install.sh
```

This copies hooks to `~/.claude/hooks/` and the init skill to `~/.claude/skills/`.

### 2. Configure credentials

Generate an API key from your Relentless account settings. Create `~/.claude/decs-config.json`:

```json
{
  "relentlessApiKey": "rlnt_your_key_here",
  "relentlessUrl": "https://relentless.build",
  "buildspaceId": "your-buildspace-id"
}
```

Your Buildspace ID is the UUID in the URL bar when logged in (e.g. `/workspace/019c2f...`).

### 3. Enable in a repo

In Claude Code, run:

```
/init-decs-project <project-node-id> [project-name]
```

This creates a "project-name - Decisions" space inside your Relentless project node and writes `.decs.json` to the repo root. Get the project node ID by clicking its kind tag (e.g. `PROJECT`) in Relentless.

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

## License

MIT
