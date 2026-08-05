# Relentless DECS

DECS v2 session bootstrap, awareness, and decision-hygiene hooks + MCP
server for [Relentless](https://relentless.build) projects, packaged as a
Claude Code plugin.

## Requirements

**Claude Code >= 2.1.214.** Below that version, `SessionStart`'s `source`
field cannot distinguish a forked conversation window from a resumed one,
and this plugin would incorrectly re-attach a forked window's DECS session
to the window it was forked from.

## Install

Two commands:

```bash
claude plugin marketplace add RelentlessToph/relentless-decs
claude plugin install relentless-decs@relentless-decs-marketplace
```

**Note:** declaring `relentless-decs` under `enabledPlugins` in your Claude
Code settings is not sufficient by itself to complete an install on current
Claude Code — run the `claude plugin install` command above too.

## Full documentation

Agent-facing setup and usage docs live at
[relentless.build/docs/decs-agent](https://www.relentless.build/docs/decs-agent).
