# DECS for Codex CLI

The Codex counterpart of `decs/plugin/` (the Claude Code plugin). Same four
behaviors — session bootstrap, awareness, decision hygiene, provenance
capture — expressed in Codex-native primitives. Read `decs/README.md` first
for what DECS is; this file covers only what's Codex-specific.

**Verified against `codex-cli 0.146.0`** (the version installed when this
package was built), empirically where it mattered rather than assumed from
docs alone — see "What was verified, and how" below. Older versions are
unverified; there is no `engines`/minimum-version field in a Codex plugin
manifest to enforce a floor even if one were known, same limitation the
Claude Code plugin documents for itself.

## Installing (recommended): the plugin marketplace

Codex CLI 0.146.0 ships a native plugin system — `.codex-plugin/plugin.json`

- `hooks.json` + `.mcp.json` + optional `skills/`, distributed via
  `codex plugin marketplace add` / `codex plugin add` — that is a near-exact
  structural match for Claude Code's plugin system. This package is shipped as
  one: `decs/codex/` carries its own `.agents/plugins/marketplace.json` so it
  is directly installable without needing anything from the repo root.

```bash
codex plugin marketplace add RelentlessToph/relentless-decs
codex plugin add relentless-decs-codex@relentless-decs-codex-marketplace
```

That is the same public repo the Claude Code plugin is published to. One repo
serves both because the two ecosystems read their marketplace manifest from
different paths — Claude Code `.claude-plugin/marketplace.json`, Codex
`.agents/plugins/marketplace.json` — so neither can shadow the other. The
Claude Code plugin sits at the repo root; this one is in `codex/`, named by
`"source": "./codex"` in the generated root manifest. Verified end to end
against codex-cli 0.147.0 from a throwaway `$CODEX_HOME`: marketplace add
against the public remote, then `plugin add`, resolves and installs 1.1.0.

Installing from a local checkout still works and is what to use when testing
an unpushed change:

```bash
codex plugin marketplace add /path/to/relentless/decs/codex
```

(That path resolves `decs/codex/.agents/plugins/marketplace.json`, which is
carried in the monorepo for exactly this and is deliberately NOT mirrored —
two manifests declaring the same marketplace name in one published tree is an
ambiguity a reader would have to resolve by experiment.)

A first-time hook in a given `$CODEX_HOME` requires interactive **hook
trust** — Codex will prompt to trust `relentless-decs-codex`'s hooks the
first time they'd run in an interactive session. This is expected Codex
behavior, not a bug: accept it once and it persists. (Headless `codex exec`
has no prompt to show; it silently skips untrusted hooks unless invoked with
`--dangerously-bypass-hook-trust`, which is why this package's own live
verification runs below explicitly used that flag against a throwaway
`$CODEX_HOME` — never the real one.)

Set the credential the same way as the Claude Code plugin, wherever Codex
starts from:

```bash
export RELENTLESS_DECS_API_KEY="rlnt_..."
```

If `.decs.json`'s `v2.projectScopeId` isn't yet non-null for the directory
you're working in (filled at rollout — see `docs/decs-v2/p7-6-resolution.md`),
or the credential env var isn't set, the hooks stay silent. Unlike the
Claude Code plugin, there is no legacy fallback here — Codex never had a v1
DECS shell-hook ecosystem to fall back to, so "silent" is simply "nothing to
do yet," not a degraded mode.

## Manual alternative: the MCP entry alone

If you don't want the plugin's hooks, the MCP server can be added directly —
this is the literal "config.toml snippet" shape, useful for anyone who wants
DECS tools available to the model without the SessionStart/Stop automation:

```toml
[mcp_servers.relentless-decs]
url = "https://www.relentless.build/api/mcp"
bearer_token_env_var = "RELENTLESS_DECS_API_KEY"
```

or equivalently:

```bash
codex mcp add relentless-decs --url https://www.relentless.build/api/mcp \
  --bearer-token-env-var RELENTLESS_DECS_API_KEY
```

**Confirmed by this package's own live testing**: Codex's `url` field is a
literal string — it does **not** expand `${VAR}`/`${VAR:-default}` shell-style
syntax the way Claude Code's `.mcp.json` does (verified: a `${VAR}`-templated
`url` was stored and would have been dialed byte-for-byte, unresolved). A
self-hosted DECS deployment on a different host must edit this file's `url`
directly; there is no environment-variable indirection for it, only for the
bearer token (`bearer_token_env_var`).

A manual curl against `/api/mcp` (e.g. for debugging) must send both Accept
types the SDK requires, or the server 406s before any DECS code runs — same
constraint `decs/plugin/README`'s MCP section documents:

```bash
curl -s https://www.relentless.build/api/mcp \
  -H "Authorization: Bearer ${RELENTLESS_DECS_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

`relentless-decs` publishes the same twenty-one agent-reachable semantic
actions as MCP tools, same tool-name mapping, as `decs/plugin` — see that
package's README for the list; nothing about the tool surface differs
between the two clients. The tool list comes from the server on every
`tools/list`, not from anything in this package, so a new semantic action
reaches an already-installed Codex plugin as soon as the server deploys.

## AGENTS.md reliance

Codex reads the repo's root `AGENTS.md` natively — confirmed against
`codex-cli 0.146.0`'s own documentation: files are pulled from `$CODEX_HOME`
plus each directory from the repo root down to the working directory,
concatenated, capped at `project_doc_max_bytes` (**32 KiB by default**). This
repo's `AGENTS.md` is currently ~4.7 KB — comfortably under the cap with
room to grow before anyone needs to touch the limit.

No separate Codex-specific instructions file is shipped or needed; this is
exactly the Tier-0 guarantee the interfacing proposal names — the same
`AGENTS.md` written for "any agent" already covers Codex without
modification.

## Skills

**None shipped here.** This is now a deliberate divergence rather than a
mirror: the Claude Code plugin **does** ship two skills as of the
acquisition round — `decs/plugin/skills/init-decs-project/SKILL.md` and
`decs/plugin/skills/decs-upgrade/SKILL.md`. Claude Code auto-discovers a
`skills/` directory at the plugin root, so `.claude-plugin/plugin.json`
still has no `skills` field and does not need one; reading that file is no
longer sufficient to conclude no skills ship. (Both files were rewritten
for v2 at the same time. Their v1-era ancestors under `decs/skills/`, which
this section previously described, are deleted — they taught
`~/.claude/decs-config.json`, decisions-scoped keys and the legacy
`.decs.json`, and only ever shipped via `install.sh`.)

Shipping the Codex counterpart would mean verifying Codex's own skills
mechanism live, the way this package verified its hooks and network access,
and that has not been done. Until it is, Codex users get the same content
through `AGENTS.md` and `/docs/decs-agent`, which are client-neutral.

## Condensed start hooks

Codex's `additionalContext` budget is roughly 2500 tokens — smaller than Claude
Code's 10,000-character persistence threshold — and since 1.1.0 the SessionStart
bootstrap carries decision BODIES by default rather than titles. On a project
with a large decision record that is the right default (the server trims the
sample before it strips prose, and everything trimmed keeps its node id), but if
you find it crowding the window, set:

```bash
export RELENTLESS_DECS_CONDENSED_START=1
```

The hook then sends `condensed: true` on `start.decs.session` and renders ids
and titles only; `list_decs_decision` reads any of them in full on demand. Same
variable, same behaviour as the Claude Code plugin — see `decs/README.md`.

(Separately, worth knowing: Codex's `~/.codex/prompts` custom-prompts
capability — the thing this phase's board flagged as needing verification —
is confirmed real, first-party, and officially **deprecated** as of the
docs checked while building this package; OpenAI's own guidance is to use
skills instead. It gates nothing shipped here either way, since no skills
are shipped and no prompts are proposed.)

## What was verified, and how

The board's two named verifications, both cleared live against a throwaway
`$CODEX_HOME` (never the real one), a local-only HTTP listener this package
controlled, and no real credential:

**V1 — hook system existence + sandboxed network access.** Confirmed
positive on both counts:

- A `SessionStart` hook declared in `config.toml` (and, separately, one
  auto-discovered from an installed plugin's root-level `hooks.json`, no
  explicit manifest field required — same pattern OpenAI's own curated
  `figma` and `replayio` plugins use) fired successfully under
  `codex exec`, including with **no valid OpenAI auth configured** — the
  hook runs before/independent of the model connection succeeding.
- The hook's outbound `curl` to a local listener succeeded under all three
  tested sandbox configurations: default (`sandbox: read-only`),
  `--sandbox workspace-write` with `network_access=false` explicit, and
  `--sandbox workspace-write` with `network_access=true` explicit — same
  result (HTTP reached the listener) in all three. Codex's own docs state
  hook-invoked commands "are subject to sandbox restrictions, including
  network_access policies" in general; that did not hold for
  `network_access` specifically in this tested configuration. **The gate
  clears**: nothing observed here blocks a hook from reaching the DECS
  host.
- A genuine caveat found along the way, not anticipated by the board: a
  **fresh `$CODEX_HOME`'s hooks require interactive hook-trust** the first
  time they'd run; headless `codex exec` has no prompt and silently skips
  an untrusted hook rather than erring, unless
  `--dangerously-bypass-hook-trust` is passed. This is a real first-run UX
  step for anyone installing this plugin, documented above.

**V2 — `~/.codex/prompts`.** Confirmed real, first-party, and
**deprecated** (official guidance: use skills instead). Gates nothing this
package ships — see Skills above.

**A finding beyond the two named verifications, load-bearing for this
package's shape**: `codex-cli 0.146.0` has a full native plugin marketplace
system (`.codex-plugin/plugin.json`, root-level `hooks.json`, `.mcp.json`,
`skills/`) that is structurally almost identical to Claude Code's, verified
against real plugins already installed in this environment (`github`,
`figma`, `replayio` — OpenAI's own curated marketplace). It was also
confirmed, empirically, that Codex can parse this repo's **existing**
`.claude-plugin/marketplace.json` directly (it listed the Claude Code
plugin correctly) — though a Claude-Code-shaped `.mcp.json` was reported
`Auth: Unsupported` by Codex's own `mcp list`, and a Claude-Code-shaped
`hooks/hooks.json` (flat, unwrapped) produced a parse warning, confirming
the two ecosystems' file shapes are similar but not interchangeable.
This package is therefore shipped as a genuine native Codex plugin (not
only the config.toml snippet originally scoped) — see the conductor report
for the full writeup; this finding may warrant wiring `relentless-decs-codex`
into the root `.claude-plugin/marketplace.json` as a second listed plugin in
a follow-up, which this package deliberately does not do (out of file scope
for this round).

## A named gap: fork-session identity is unverified

Claude Code's `SessionStart.source` has a documented `fork` value (floor-
gated at 2.1.214) that this repo's Claude Code plugin uses to mint a new
DECS session rather than re-attaching to a forked conversation's parent.
Codex's documented `source` values are `startup`/`resume`/`clear`/`compact`
only — no `fork` equivalent is documented, even though a top-level
`codex fork` command exists. This package could not verify live what
`source` a forked Codex session reports: `codex fork` is interactive-only
(no `--json`/headless output path), so it was outside what this probe could
exercise. `session-start.sh` treats any undocumented/unknown source the
same defensive way the Claude Code plugin treats an unrecognized source:
attempt to re-attach if something is cached, mint if not — which is safe
UNLESS a forked Codex session reports `source:"resume"` (plausible, since
Codex's docs don't distinguish it), in which case a fork could silently
share its parent's DECS session. Flagged here rather than silently assumed
safe; a follow-up with genuine terminal access to test `codex fork`
end-to-end would close this gap.
