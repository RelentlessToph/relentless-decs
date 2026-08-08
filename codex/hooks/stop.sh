#!/bin/bash
# decs-version: 1.1.1 (relentless-decs-codex plugin)
#
# DECS v2 — Codex Stop hook: hygiene check, BLOCKING per ratified Q1
# (docs/decs-v2/ai-interfacing-proposal.md §6) with the
# hooks-evolution-brief.md §2.7 lever: block-with-reason only when there is
# plausibly something to record; when the only news is unread awareness,
# use the non-blocking additionalContext channel instead.
#
# Exactly one hygiene touchpoint per native session (hygiene-done flag,
# same marker-file pattern as decs/hooks/decs-stop.sh and the Claude Code
# plugin's stop.sh).
#
# No legacy mode: Codex never had a v1 DECS hook ecosystem, so unlike the
# Claude Code plugin's stop.sh there is nothing to delegate to when no v2
# session was bootstrapped this turn — this hook simply exits quietly.
#
# Standing rule, unconditional: NEVER block because DECS itself is slow or
# unreachable. A network failure degrades to silence; a clean 401/403
# (credential known-dead) gets one quiet non-blocking note, never a block.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/decs-v2-common.sh
source "$PLUGIN_ROOT/hooks/lib/decs-v2-common.sh"

INPUT=$(cat 2>/dev/null || true)
CODEX_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_ID=$(decs_v2_session_id "$CODEX_SESSION_ID")
HYGIENE_DONE="/tmp/decs-v2-codex-hygiene-done-${SESSION_ID}"

if [ -f "$HYGIENE_DONE" ]; then
    rm -f "$HYGIENE_DONE"
    exit 0
fi

CACHED=$(decs_v2_read_session_cache "$SESSION_ID")

if [ -z "$CACHED" ]; then
    # No v2 session bootstrapped this turn — nothing to check, no fallback
    # to run (see header). Stay silent.
    exit 0
fi

PROJECT_SCOPE_ID=$(printf '%s' "$CACHED" | jq -r '.projectScopeId // empty' 2>/dev/null)
DECS_SESSION_ID=$(printf '%s' "$CACHED" | jq -r '.decsSessionId // empty' 2>/dev/null)
HOST=$(printf '%s' "$CACHED" | jq -r '.host // empty' 2>/dev/null)
API_KEY="${RELENTLESS_DECS_API_KEY:-}"

if [ -z "$PROJECT_SCOPE_ID" ] || [ -z "$DECS_SESSION_ID" ] || [ -z "$HOST" ] || [ -z "$API_KEY" ]; then
    # Cache present but incomplete, or the credential env var disappeared
    # mid-session — nothing safe to do. Mark done so this doesn't repeat
    # every Stop for the rest of the session.
    touch "$HYGIENE_DONE"
    exit 0
fi

# input omits its own decsSessionId, so it defaults to the envelope-level
# one presented below — guaranteeing ownSession:true and therefore an
# unreadByEventType field in the response.
ENVELOPE=$(jq -n --arg scope "$PROJECT_SCOPE_ID" --arg session "$DECS_SESSION_ID" \
    '{target:{scopeId:$scope}, decsSessionId:$session, input:{}}')

RESPONSE=$(decs_v2_call "$HOST" "list.decs.communication" "$API_KEY" "$ENVELOPE" 3)
CODE=$(printf '%s' "$RESPONSE" | tail -n1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

touch "$HYGIENE_DONE"

RECORD_HINT="Record decisions via the MCP tool add_decs_decision (never a raw curl typed by hand — see decs/README.md). Target scope: ${PROJECT_SCOPE_ID}. Session: ${DECS_SESSION_ID}. Before recording, check whether an existing decision already covers this ground with list_decs_decision — one amended record beats two that disagree, and update_decs_decision needs the version that read returns."

if [ "$CODE" != "200" ]; then
    if [ "$CODE" = "401" ] || [ "$CODE" = "403" ]; then
        REASON="DECS v2: this session's credential stopped authenticating (HTTP ${CODE}) — hygiene and recording are unavailable this session. If you were removed from the project or the credential was revoked, a new project-scoped credential needs to be minted from the project's DECS panel. Nothing else to do — you may end the session."
        jq -n --arg reason "$REASON" '{"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": $reason}}'
    fi
    # Network/timeout/5xx/unexpected: silent fail-open, no block, no note.
    exit 0
fi

UNREAD_TOTAL=$(printf '%s' "$BODY" | jq '[(.output.unreadByEventType // {}) | to_entries[] | .value] | add // 0' 2>/dev/null)
case "$UNREAD_TOTAL" in
    ''|*[!0-9]*) UNREAD_TOTAL=0 ;;
esac

if [ "$UNREAD_TOTAL" -gt 0 ]; then
    UNREAD_SUMMARY=$(printf '%s' "$BODY" | jq -r \
        '(.output.unreadByEventType // {}) | to_entries | map(select(.value > 0)) | map("\(.key) x\(.value)") | join(", ")' \
        2>/dev/null)
    REASON="DECS v2: this session has unread communications waiting — ${UNREAD_SUMMARY}. Review via the MCP tool list_decs_communication (or list_decs_question for question threads) and acknowledge what you've handled. ${RECORD_HINT}"
    jq -n --arg reason "$REASON" '{"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": $reason}}'
    exit 0
fi

REASON="DECS v2 Decision Hygiene Check: before ending, review this session for decisions worth recording — technology/API/architecture choices, insights about how the system works or should, constraints discovered, or reversals of prior decisions. ${RECORD_HINT} If there is nothing worth recording, say so and stop."
jq -n --arg reason "$REASON" '{"decision": "block", "reason": $reason}'
exit 0
