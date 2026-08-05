---
name: init-decs-project
description: Set up DECS for this repository — verify the project-scoped credential a human gives you, place it where Claude Code will find it, write .decs.json, and install the Relentless DECS plugin. Use when a human pastes a DECS setup prompt or a credential, or asks to set up DECS, connect DECS, init DECS, enable decision tracking, or record decisions to Relentless from this repo.
allowed-tools: Bash, Read, Write, Edit
---

# Set up DECS for this repository

DECS is persistent collaboration memory for a project: an agent files the
decisions it makes, asks the project's humans asynchronous questions, and
gets the project's evolving truth back at the start of every session. This
skill connects one repository to one DECS **project scope** so that all of
that works here.

Five steps, in order. The fourth is the only one that changes a tracked
file; the third is the only one that touches a secret.

**DECS never gates work.** If any step fails, say so once, plainly, and
carry on with whatever the human actually asked you to build. Never stall a
task because DECS is not set up.

## What you need before you start

The human is your source for all three of these. Ask for anything missing —
never guess, and never carry an id over from another repository:

- **A project-scoped credential.** A Bearer token bound to exactly one
  project scope. You cannot mint one; a human does it in the Relentless web
  app. If they do not have one yet, tell them: open the project in
  Relentless, scroll to the **DECS** section, find **Credentials**, click
  **+ New**, and copy what it shows — that is the only time the credential
  is displayed in full. Any live member of the project can do this; it is
  not owner-only.
- **The project scope id.** The id of the project scope this repository
  records to. It is not a node id and it is not the project's name.
- **The host.** The origin of the Relentless deployment that backs DECS,
  normally `https://www.relentless.build`.

The setup prompt Relentless generates at mint time carries all three. If
the human pasted that prompt, read the values out of it rather than asking
again.

## Step 1 — Read the agent documentation

```bash
curl -s "{host}/docs/decs-agent"
```

This is the authoritative agent-facing guide to DECS: the action
vocabulary, the request envelope, the credential model, and the failure
modes. It is short. Read it before you configure anything, because
everything below assumes it.

If the fetch fails, note it and continue — the steps here stand on their
own.

## Step 2 — Verify the credential

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer <the credential>" \
  "{host}/api/semantic-definitions"
```

**A 200 from this endpoint is the only definition of success in this whole
skill.** It is the only evidence that the credential is alive, belongs to a
project, and reaches a deployment with DECS turned on. Having written the
files proves nothing.

Anything other than 200 means stop. Report exactly what you got and what it
means; do not retry in a loop, do not try a different URL, and do not guess
at a fix:

- **401** — no credential was presented, or it is expired or revoked. A
  project-scoped credential derives its validity from live project
  membership on every call, so it also returns 401 the moment the person
  who minted it leaves the project. Ask the human to mint a fresh one.
- **403** — authenticated, but not permitted for this project scope.
- **404** — this deployment does not have DECS v2 enabled. Check the host.
- **429** — rate limited. Wait; do not retry in a loop.

Run this verification **before** writing the credential anywhere. There is
no reason to store a token you have not proven works.

## Step 3 — Place the credential

**Canonical location: this repository's `.claude/settings.local.json`**, in
its `env` block, as `RELENTLESS_DECS_API_KEY`.

```json
{
  "env": {
    "RELENTLESS_DECS_API_KEY": "<the credential the human just gave you>"
  }
}
```

Merge into the file if it already exists — never overwrite it, it holds the
human's own local settings.

Why per-repository and not a global environment variable: a
project-scoped credential is bound to exactly **one** project scope. One
global slot works until the human opens a second DECS-recording repository,
and then it silently answers about the wrong project — a failure that looks
like working software. A shell profile export is a reasonable shortcut for
someone who only ever works in one DECS project; if you choose that, say
the tradeoff out loud rather than deciding it silently for them.

**Confirm the file is ignored by git before you write the credential into
it:**

```bash
git check-ignore -v .claude/settings.local.json
```

An exit code of 0 with a matching ignore rule means you are safe to write.
If it prints nothing, the file is **tracked or ignorable-by-convention
only** — stop, tell the human that writing the credential there would put a
live secret in a committable file, and let them add the ignore rule (or
pick the shell-profile route) before you continue.

Never write the credential into a tracked file. Never commit it. Never echo
it back in full. After you write it, tell the human exactly which file now
holds their credential.

## Step 4 — Write `.decs.json`

At the repository root, and additionally inside each app directory of a
monorepo that records to its own project scope:

```json
{
  "v2": {
    "projectScopeId": "<the project scope id>",
    "host": "<the DECS backend origin>"
  }
}
```

This file is committed on purpose. It is the machine-readable marker for
which DECS project this code records to, it carries no secret, and every
teammate and agent reads their project identity out of it rather than
holding one in their own config.

If the file already exists, edit it rather than replacing it. It may carry
older v1 keys such as `relentlessSpaceId` alongside `v2` — leave those
exactly where they are; a separate legacy path still reads them.

In a monorepo, `host` is the same origin in every directory. Identity
varies per directory; the backend does not.

Commit it, and say that you did.

## Step 5 — Install the plugin, then ask for a restart

Requires Claude Code 2.1.214 or newer. Below that version, `SessionStart`'s
`source` field cannot tell a forked conversation from a resumed one, and two
windows would silently share one DECS session. Check with
`claude --version` first.

```
claude plugin marketplace add RelentlessToph/relentless-decs
claude plugin install relentless-decs@relentless-decs-marketplace
```

Run **both**. Being listed under `enabledPlugins` in a settings file does
not by itself complete an installation on current Claude Code — a
repository can declare the marketplace and the plugin and still have
nothing installed until the explicit install command runs. If you are ever
troubleshooting a plugin that "should" be active because settings mention
it, that is the first thing to check.

Then **ask the human to restart the session.** Hooks, plugin state, and the
`env` block you just wrote are all read at startup; nothing you did in
steps 3 through 5 takes effect in the conversation you are currently in.
This is the end of the skill — you cannot verify the plugin from inside the
session that predates it.

## Report

Tell the human, in plain sentences:

- The HTTP status the catalog fetch returned, and that 200 is what proved
  setup worked.
- Which file now holds their credential.
- Where `.decs.json` was written, and that you committed it.
- That the plugin is installed and the session needs a restart before DECS
  is live.

If something failed, report the step and the status code, and be explicit
that DECS is not set up. Then get back to the work in front of you. DECS
never gates work.
