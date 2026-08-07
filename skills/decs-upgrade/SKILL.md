---
name: decs-upgrade
description: Check whether DECS is actually working in this repository, and migrate a v1 install (decs-config.json, hand-installed ~/.claude/hooks scripts, a decisions-scoped rlnt_ key, a .decs.json carrying only relentlessSpaceId) to the v2 plugin and a project-scoped credential. Use when DECS seems silent, stale, or misconfigured, when a human asks to upgrade or fix DECS, or when both the old shell hooks and the plugin appear to be installed at once.
allowed-tools: Bash, Read, Write, Edit
---

# Check and upgrade DECS

Two jobs, in this order: find out what state DECS is actually in here, then
either repair it or migrate it forward. Do the diagnosis first — a lot of
"DECS is broken" turns out to be one dead credential, and a lot of "DECS is
fine" turns out to be a v1 install that has been quietly recording to a
place nobody reads.

**Silence is DECS's designed failure mode.** DECS never blocks work, which
means a completely broken DECS looks exactly like a DECS with nothing to
say. Never conclude things are fine because nothing errored. Only the
catalog fetch in Check 3 proves anything.

## Diagnose: the three checks

All three must pass. There is no partial "working."

**Check 1 — project identity.** Read `.decs.json` at the repository root
(and in each app directory of a monorepo). It must carry a `v2` block whose
`projectScopeId` is present and **not null**.

```bash
cat .decs.json
```

- `v2.projectScopeId` is a real id — good, continue.
- `v2.projectScopeId` is `null` — this directory declares a v2 identity but
  was never linked to a concrete project scope. This is a documented,
  non-error state, not a bug. A human links it in the app; nothing will
  record until they do.
- No `v2` block at all, only `relentlessSpaceId` — this is a **v1** repo.
  Go to _Migrating from v1_ below.
- No `.decs.json` anywhere — this repository does not record to DECS.
  Offer `/init-decs-project`; do not assume.

**Check 2 — a credential is visible.** The project-scoped credential
belongs in this repository's `.claude/settings.local.json` under `env` as
`RELENTLESS_DECS_API_KEY`. A shell-profile export also works.

```bash
grep -l RELENTLESS_DECS_API_KEY .claude/settings.local.json 2>/dev/null
[ -n "$RELENTLESS_DECS_API_KEY" ] && echo "set in this environment"
```

Note that the `env` block is read at session start, so a credential written
during this session is present in the file but absent from your environment
until the human restarts. That is expected, not a failure.

**Check 3 — the catalog fetch.** This is the only check that proves
anything.

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $RELENTLESS_DECS_API_KEY" \
  "{host}/api/semantic-definitions"
```

`{host}` is `v2.host` from `.decs.json`. 200 means DECS is set up and live.
Anything else means it is not:

- **401** — no credential presented, or it is expired or revoked. A
  project-scoped credential derives its validity from live project
  membership on every call, so it also dies the moment its minter leaves
  the project. The human mints a fresh one.
- **403** — authenticated, but not permitted for this project scope. Most
  often the credential belongs to a different project than the one in this
  repository's `.decs.json`.
- **404** — this deployment does not have DECS v2 enabled. Check `v2.host`.
- **429** — rate limited. Wait; do not retry in a loop.

If all three pass and DECS still seems absent, the credential and the
project scope are fine and the missing piece is the integration layer — the
plugin, the MCP entry, or the hooks. Go to _Is the plugin actually
installed?_ below.

## Detect v1 leftovers

v1 DECS was a hand-installed set of shell scripts driven by a global config
file and a decisions-scoped API key. The v2 plugin supersedes all of it.
Look for these:

```bash
ls ~/.claude/decs-config.json ~/.claude/decs-installed.json 2>/dev/null
ls ~/.claude/hooks/get-decisions.sh ~/.claude/hooks/decs-context.sh \
   ~/.claude/hooks/decs-stop.sh 2>/dev/null
grep -n "get-decisions\|decs-context\|decs-stop" ~/.claude/settings.json 2>/dev/null
```

What each one means:

- **`~/.claude/decs-config.json`** — the v1 credential and identity file
  (`relentlessApiKey`, `relentlessUrl`, `buildspaceId`). v2 reads none of
  it. The key inside it is a **decisions-scoped `rlnt_` API key**, which is
  a different thing from a project-scoped credential: it was restricted to
  `decision` and `decs` node kinds across a whole buildspace, and it cannot
  authenticate a single semantic action. It is not upgradable — a
  project-scoped credential has to be minted fresh.
- **`get-decisions.sh` / `decs-context.sh` / `decs-stop.sh` in
  `~/.claude/hooks/`, plus matching entries in `~/.claude/settings.json`** —
  the v1 hook install. If the plugin is also active, **every SessionStart,
  UserPromptSubmit and Stop now fires twice**, once from each install. That
  is the single most common symptom of a half-finished migration.
- **`.decs.json` carrying only `relentlessSpaceId`** — v1 project identity:
  a DECS container node id, not a project scope id. The two are not
  interchangeable and one cannot be derived from the other.
- **`~/.claude/decs-installed.json`** — v1 install metadata (version,
  timestamp, file list). Harmless, and useful evidence of what was
  installed; it means nothing to v2.

## Migrating from v1

There is no in-place conversion. v1 identity is a node id and v1 auth is a
buildspace-wide decisions-scoped key; v2 identity is a project scope id and
v2 auth is a credential bound to that one project scope. Both have to be
obtained fresh.

1. **Ask the human to mint a project-scoped credential.** You cannot do
   this — no agent can. Tell them the exact path: open the project in
   Relentless, scroll to the **DECS** section on the project, find
   **Credentials**, click **+ New**, and copy what it shows. That is the
   only time the credential is displayed in full. Any live member of the
   project can mint one; it is not owner-only. They will also need to tell
   you the **project scope id** for this repository.
2. **Then follow `/init-decs-project`.** It is the canonical path: read the
   agent docs, verify the credential with a catalog fetch, place the
   credential in `.claude/settings.local.json`, write the `v2` block into
   `.decs.json`, install the plugin, restart. Do not improvise a shorter
   version of it here.

When you write the `v2` block, **leave `relentlessSpaceId` in place.** The
v2 block is added alongside it, not in place of it. The two identities
coexist deliberately, and the legacy path still reads the old key.

## Is the plugin actually installed?

```bash
claude --version
claude plugin list 2>/dev/null | grep -i relentless
```

The plugin requires Claude Code **2.1.214 or newer**. Below that,
`SessionStart`'s `source` field cannot distinguish a forked conversation
from a resumed one, and two windows would silently share one DECS session.

```
claude plugin marketplace add RelentlessToph/relentless-decs
claude plugin install relentless-decs@relentless-decs-marketplace
```

Run both. A repository can declare the marketplace in
`extraKnownMarketplaces` and the plugin in `enabledPlugins` and still have
nothing installed — on current Claude Code, being listed does not complete
an installation. When settings mention a plugin that clearly is not
running, check this first.

### Is it recent enough? (a fourth thing worth checking)

`claude plugin list` reports the installed version. **Below 1.1.0**, DECS is
working but is telling this session much less than it could:

- SessionStart injects key-decision TITLES only, with no node ids attached,
  so nothing in the session can expand one.
- Ordinary (non-key) decisions are invisible entirely.

1.1.0 injects the full what / why / purpose / constraints of the project's
key decisions and its ten most recent ordinary ones, each with a node id.
Update with:

```
claude plugin update relentless-decs@relentless-decs-marketplace
```

Note that the READ TOOLS — `list_decs_decision`, `list_decs_plan`,
`list_decs_project` — do **not** depend on the plugin version at all. The MCP
server is remote and builds its tool list from the live registry, so those
appear in `/mcp` on any installed version. Only the hook's injection changes
with the plugin. If the tools are missing, the problem is the credential or
the deployment, never a stale plugin.

## Cleaning up v1 artifacts

**Only with the human's explicit confirmation, one item at a time.** These
are files in their home directory that you did not create, and some of them
still work. Show them what you found and what removing it would mean; let
them decide.

The one cleanup worth actively recommending is the double-firing hooks: if
the plugin is installed and `~/.claude/settings.json` still carries the v1
`get-decisions` / `decs-context` / `decs-stop` entries, every one of those
three events runs twice per session. Removing those three entries from
their personal `~/.claude/settings.json` — never the repository's committed
`.claude/settings.json` — fixes it, and the plugin does everything those
scripts did.

**Sequence the removal around a restart, not before it.** Claude Code
hot-reloads the hooks section of `settings.json` into every RUNNING
session, but plugin hooks only apply at session start — the two do not
change over at the same moment. Remove the v1 entries while sessions are
open and every one of them loses DECS coverage live (no more decision
injection, no more hygiene check), with nothing replacing it until
restart; this was learned by breaking the DECS development machine itself.
The double-firing window is the safe state; the coverage hole is the
dangerous one. So: confirm the plugin actually loads (`claude plugin
list` shows it enabled, no error), let the human finish or restart their
open sessions, and remove the three entries as the last step — never
first.

`~/.claude/decs-config.json` still drives the plugin's legacy fallback mode
for any _other_ repository that has a v1 `.decs.json` and no v2 identity.
Deleting it is safe only once every repository the human works in has moved
to v2. Say that before they delete it, rather than after.

## Report

Say plainly:

- Which of the three checks passed, and the exact status code the catalog
  fetch returned.
- What v1 leftovers you found, and specifically whether hooks are firing
  twice.
- What changed, what needs a session restart, and what still needs a human
  (minting a credential, linking a null `projectScopeId`).

If DECS is not working and cannot be fixed in this session, say so once and
get back to the work in front of you. DECS never gates work.
