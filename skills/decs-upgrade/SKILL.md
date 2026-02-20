---
name: decs-upgrade
description: Upgrade DECS to the latest version. Migrates from old unscoped API key to new DECS-scoped key, updates hooks, and verifies configuration. Run when DECS hooks are out of date or after updating via install.sh.
disable-model-invocation: true
allowed-tools: Bash, Read, Write
---

# DECS Upgrade

This skill walks you through upgrading a DECS-enabled project to the latest DECS version. Work through each upgrade step that applies.

## Current State

- **DECS config**: !`cat ~/.claude/decs-config.json 2>/dev/null || echo "NOT FOUND"`
- **Project config**: !`cat .decs.json 2>/dev/null || echo "NOT FOUND — this repo may not be DECS-enabled"`
- **Hooks installed**: !`ls ~/.claude/hooks/get-decisions.sh ~/.claude/hooks/decs-context.sh ~/.claude/hooks/decs-stop.sh 2>/dev/null || echo "MISSING"`

If project config is missing, tell the user to run `/init-decs-project` first and stop.

## Relentless API Config

```bash
DECS_CONFIG="$HOME/.claude/decs-config.json"
API_KEY=$(jq -r '.relentlessApiKey // empty' "$DECS_CONFIG")
BASE_URL=$(jq -r '.relentlessUrl // empty' "$DECS_CONFIG")
BUILDSPACE_ID=$(jq -r '.buildspaceId // empty' "$DECS_CONFIG")
```

---

## Upgrade Checklist

Work through each section below. Skip sections where the check already passes.

---

### Upgrade 1: Migrate to DECS-Scoped API Key (Feb 2026)

**What changed**: Every Relentless buildspace now has two separate API keys:

| Key                    | Scope                          | Purpose                     |
| ---------------------- | ------------------------------ | --------------------------- |
| **Buildspace API Key** | Full access to all node kinds  | General API use             |
| **DECS API Key**       | `decision` + `decs` nodes only | DECS hooks and integrations |

DECS hooks should use the **DECS-scoped key** for principle of least privilege. Shell hooks running on the user's machine should not have access to the full buildspace.

**Check**: Test if the current key can access non-DECS node kinds (which would mean it's the full key, not the DECS key):

```bash
# Try to list notebook nodes — a DECS key would return 403 or empty results
response=$(curl -s "${BASE_URL}/api/nodes?kind=notebook&buildspaceId=${BUILDSPACE_ID}" \
  -H "Authorization: Bearer ${API_KEY}")

# Check if we got nodes back (full key) or an error/empty (DECS key)
node_count=$(echo "$response" | jq '.nodes | length' 2>/dev/null)
has_error=$(echo "$response" | jq -r '.error // empty' 2>/dev/null)
```

**If `node_count > 0` (full key detected)** — this upgrade is needed:

Tell the user:

> Your DECS config is using the **full buildspace API key**, which gives shell hooks access to your entire buildspace. For security, DECS hooks should use the restricted **DECS API Key** that can only access decision and DECS nodes.
>
> To swap the key:
>
> 1. Open your Relentless profile (sidebar → Settings)
> 2. Find the **DECS API Key** section
> 3. Copy the DECS key (starts with `rlnt_`)
> 4. I'll update your `~/.claude/decs-config.json` with the new key

Wait for the user to provide the DECS key, then update the config:

```bash
# Read current config, replace the API key
jq --arg key "NEW_DECS_KEY" '.relentlessApiKey = $key' "$HOME/.claude/decs-config.json" > /tmp/decs-config-tmp.json \
  && mv /tmp/decs-config-tmp.json "$HOME/.claude/decs-config.json" \
  && chmod 600 "$HOME/.claude/decs-config.json"
```

**If `has_error == "scope_restricted"` or `node_count == 0`** — already using DECS key, skip this step.

**Verify** after updating:

```bash
# Test DECS key works for decisions
curl -s "${BASE_URL}/api/nodes?kind=decision&buildspaceId=${BUILDSPACE_ID}" \
  -H "Authorization: Bearer $(jq -r '.relentlessApiKey' ~/.claude/decs-config.json)" \
  | jq '.nodes | length'
```

If this returns a number (even 0), the key works for its intended purpose.

---

### Upgrade 2: Remove Legacy Linear Config (if present)

**What changed**: DECS previously supported Linear as a storage backend. This is deprecated — Relentless is the only supported backend.

**Check**: Does `~/.claude/decs-config.json` contain Linear-specific fields?

```bash
jq 'has("linearApiKey") or has("teamId") or has("decisionLabelId") or has("keyDecisionLabelId")' "$HOME/.claude/decs-config.json"
```

**If `true`** — remove legacy fields:

```bash
jq 'del(.linearApiKey, .teamId, .decisionLabelId, .keyDecisionLabelId, .projectId)' \
  "$HOME/.claude/decs-config.json" > /tmp/decs-config-tmp.json \
  && mv /tmp/decs-config-tmp.json "$HOME/.claude/decs-config.json" \
  && chmod 600 "$HOME/.claude/decs-config.json"
```

The config should now contain only:

```json
{
  "relentlessApiKey": "rlnt_...",
  "relentlessUrl": "https://www.relentless.build",
  "buildspaceId": "..."
}
```

---

### Upgrade 3: Update Hooks to Latest Version

**Check**: Compare installed hooks against the repo versions:

```bash
# Check if repo has newer hooks
diff ~/.claude/hooks/get-decisions.sh ./decs/hooks/get-decisions.sh 2>/dev/null
diff ~/.claude/hooks/decs-context.sh ./decs/hooks/decs-context.sh 2>/dev/null
diff ~/.claude/hooks/decs-stop.sh ./decs/hooks/decs-stop.sh 2>/dev/null
```

**If any diffs found** — re-run the installer:

```bash
./decs/install.sh
```

This copies hooks and skills from the repo to `~/.claude/` and merges hook entries into `settings.json`.

**Key changes in latest hooks:**

- `get-decisions.sh`: Layered discovery for monorepos (walks up finding ALL .decs.json files), `.nodes` wrapper handling
- `decs-context.sh`: `.nodes` wrapper handling for API response consistency
- `decs-stop.sh`: Updated hygiene message referencing DECS-scoped key, fixed PATCH endpoint format

---

### Upgrade 4: Verify Base URL

**Check**: Is the `relentlessUrl` correct?

```bash
jq -r '.relentlessUrl' "$HOME/.claude/decs-config.json"
```

The correct value is `https://www.relentless.build`. If it's `https://relentless.build` (without www), update it:

```bash
jq '.relentlessUrl = "https://www.relentless.build"' "$HOME/.claude/decs-config.json" > /tmp/decs-config-tmp.json \
  && mv /tmp/decs-config-tmp.json "$HOME/.claude/decs-config.json" \
  && chmod 600 "$HOME/.claude/decs-config.json"
```

---

### Upgrade 5: Verify Everything Works

Run the SessionStart hook and confirm output:

```bash
~/.claude/hooks/get-decisions.sh
```

You should see:

- "=== DECS: Prior Architectural Decisions ===" header
- "Key Decisions (always active)" section if any exist
- "Recent Decisions" section for non-key decisions

If the hook produces no output, check:

1. `.decs.json` exists in the repo root (or parent directory)
2. The `relentlessSpaceId` in `.decs.json` points to a valid DECS node
3. The DECS node has child decision nodes

---

## After Upgrade

Tell the user:

- What was upgraded and what changed
- Whether the key was migrated from full to DECS-scoped
- Whether legacy Linear config was cleaned up
- Whether hooks were updated to latest version
- That the next session start will use the updated configuration
