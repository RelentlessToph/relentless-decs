# Relentless DECS

DECS v2 session bootstrap, awareness, and decision-hygiene hooks + MCP
server for [Relentless](https://relentless.build) projects.

This repo carries **two plugins** — one for Claude Code, one for Codex CLI.
They are the same four behaviours expressed in each client's native
primitives, they use the same credential, and they talk to the same MCP
server. Install whichever your runtime is; installing both is fine.

## Claude Code

**Requires Claude Code >= 2.1.214.** Below that version, `SessionStart`'s
`source` field cannot distinguish a forked conversation window from a
resumed one, and the plugin would incorrectly re-attach a forked window's
DECS session to the window it was forked from.

```bash
claude plugin marketplace add RelentlessToph/relentless-decs
claude plugin install relentless-decs@relentless-decs-marketplace
```

Run both. Declaring `relentless-decs` under `enabledPlugins` in your Claude
Code settings is not sufficient by itself to complete an install on current
Claude Code.

Plugin content is at the root of this repo (`hooks/`, `skills/`,
`.mcp.json`).

## Codex CLI

Verified against `codex-cli` 0.147.0.

```bash
codex plugin marketplace add RelentlessToph/relentless-decs
codex plugin add relentless-decs-codex@relentless-decs-codex-marketplace
```

Plugin content is in [`codex/`](./codex). The first run in a given
`$CODEX_HOME` prompts once for **hook trust** — that is expected Codex
behaviour, not a fault; accept it once and it persists.

The two clients read different manifest paths — Claude Code
`.claude-plugin/marketplace.json`, Codex `.agents/plugins/marketplace.json`
— which is why one repo can serve both.

## Credential

Both plugins read `RELENTLESS_DECS_API_KEY`, a project-scoped credential a
human mints from the project's DECS section in the Relentless web app. Set
`RELENTLESS_DECS_CONDENSED_START=1` if you want session-start context as
decision ids and titles instead of full bodies.

## Full documentation

Agent-facing setup and usage docs live at
[relentless.build/docs/decs-agent](https://www.relentless.build/docs/decs-agent).
