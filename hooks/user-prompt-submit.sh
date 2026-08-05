#!/bin/bash
# decs-version: 1.0.5 (relentless-decs plugin)
#
# DECS v2 — UserPromptSubmit hook.
#
# v2 sessions get awareness on every semantic-action response (P5-8/P7-4) —
# there is no reason for a prompt-keyword-triggered re-fetch once a v2
# session is active for this native session. This hook therefore does
# NOTHING when session-start.sh already bootstrapped a v2 session this
# turn (its cache file is the signal). The v1 keyword-regex pattern
# (docs/decs-v2/hooks-evolution-brief.md §2.11) survives ONLY as the
# legacy-mode fallback — delegated verbatim to this repo's own
# decs-context.sh: v1 identity, no v2 session, unchanged behavior.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/decs-v2-common.sh
source "$PLUGIN_ROOT/hooks/lib/decs-v2-common.sh"

INPUT=$(cat 2>/dev/null || true)
CC_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID=$(decs_v2_session_id "$CC_SESSION_ID")

# v2 session already bootstrapped this turn — awareness rides action
# responses, nothing to inject here.
if [ -n "$(decs_v2_read_session_cache "$SESSION_ID")" ]; then
    exit 0
fi

REPO_ROOT=$(decs_v2_repo_root)
[ -n "$REPO_ROOT" ] || exit 0

LEGACY_SCRIPT="$REPO_ROOT/decs/hooks/decs-context.sh"
[ -f "$LEGACY_SCRIPT" ] || exit 0

printf '%s' "$INPUT" | bash "$LEGACY_SCRIPT"
