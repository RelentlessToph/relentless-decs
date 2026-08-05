#!/bin/bash
# decs-version: 1.0.5 (relentless-decs plugin)
#
# DECS v2 — SessionStart hook: session bootstrap.
#
# v2 mode (a v2 project identity resolves for $PWD AND a project-scoped
# credential is configured): register.decs.consumer once per project scope
# (cached), then start.decs.session — minting a new DECS session on
# startup/clear/fork, re-attaching by the CACHED server-issued id on
# resume/compact (never minting on re-attach). The re-attach response's own
# bootstrap context IS the re-injection on a compact SessionStart — the
# measured channel (docs/decs-v2/PROGRESS.md P7-0: SessionStart(compact) is
# the design target, fires before PostCompact, both documented and
# verified).
#
# Legacy fallback (v2 identity null/pending, or no credential configured):
# delegates verbatim to this repo's own decs/hooks/get-decisions.sh — v1
# identity, no v2 session, unchanged behavior, byte-for-byte the script
# P7-1 already fixed and matrix-tested. No v1 identity either: stay
# silent — the §6.1 not-installed offer lives in AGENTS.md, read by the
# agent directly, never a hook banner.
#
# Never blocks. Every network call is bounded (--max-time, inside
# decs_v2_call) well under this hook's 10s timeout.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=lib/decs-v2-common.sh
source "$PLUGIN_ROOT/hooks/lib/decs-v2-common.sh"

INPUT=$(cat 2>/dev/null || true)
CC_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
MODEL=$(printf '%s' "$INPUT" | jq -r '.model // empty' 2>/dev/null)
EFFORT=$(printf '%s' "$INPUT" | jq -r '.effort.level // empty' 2>/dev/null)
SESSION_ID=$(decs_v2_session_id "$CC_SESSION_ID")

REPO_ROOT=$(decs_v2_repo_root)
[ -n "$REPO_ROOT" ] || exit 0

run_legacy_fallback() {
    local legacy_script="$REPO_ROOT/decs/hooks/get-decisions.sh"
    [ -f "$legacy_script" ] || return 0
    # Re-present the same stdin JSON this hook received — get-decisions.sh
    # reads SessionStart.source from it itself (P7-1's compact-cache reuse).
    printf '%s' "$INPUT" | bash "$legacy_script"
}

if ! decs_v2_source_resolver "$REPO_ROOT"; then
    # Neither the checkout's decs/lib copy nor the plugin-bundled copy of
    # resolve-decs-identity.sh could be sourced — a damaged install.
    # Legacy hooks resolve their own identity independently, so try the
    # legacy fallback directly.
    run_legacy_fallback
    exit 0
fi

resolve_decs_identity "$PWD"
V2_SCOPE_ID="$RESOLVE_DECS_V2_SCOPE_ID"
V2_HOST="$RESOLVE_DECS_V2_HOST"
LEGACY_ID="$RESOLVE_DECS_LEGACY_ID"
API_KEY="${RELENTLESS_DECS_API_KEY:-}"

render_bootstrap_context() {
    local context="$1"
    [ -n "$context" ] && [ "$context" != "null" ] || return 0

    local text
    text=$(printf '%s' "$context" | jq -r '
        (if (.keyDecisions.count // 0) > 0 then
            "Key decisions (\(.keyDecisions.count)): " +
            ((.keyDecisions.recentTitles // []) | join("; "))
         else empty end),
        (if (.openQuestions.count // 0) > 0 then
            "Open questions (\(.openQuestions.count)): " +
            ((.openQuestions.recent // []) | map(.title) | join("; "))
         else empty end),
        (
            (.unreadByEventType // {}) as $u |
            ($u | to_entries | map(select(.value > 0))) as $nz |
            if ($nz | length) > 0 then
                "Unread: " + ($nz | map("\(.key) x\(.value)") | join(", "))
            else empty end
        ),
        (if ((.truncated // []) | length) > 0 then
            "(bootstrap context trimmed: " + ((.truncated) | join(", ")) + ")"
         else empty end)
    ' 2>/dev/null)

    local title
    title=$(printf '%s' "$context" | jq -r '.project.title // "this project"' 2>/dev/null)

    [ -n "$text" ] || text="No open decisions or questions recorded yet."

    local full="=== DECS v2: ${title} ===
${text}
Record decisions via the MCP tool add_decs_decision (or POST to
/api/semantic-actions/add.decs.decision with this project's credential —
never a raw curl typed by hand, see decs/README.md). Ask via
add_decs_question; answers surface automatically in this session's
awareness — no need to re-poll."

    jq -n --arg ctx "$full" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'
}

run_v2_bootstrap() {
    local host="${V2_HOST:-https://www.relentless.build}"
    local reattach_id=""
    local cached

    # Mint-vs-reattach from SessionStart.source. Unknown/absent source
    # (older CC, or a future value) behaves like resume rather than
    # guessing wrong in either direction: try to re-attach if something is
    # cached, mint if not.
    case "$SOURCE" in
        startup|clear|fork)
            # fork: invariant 3 (a fork is a distinct session even though
            # it is lineage-identical to its parent). The version floor
            # (2.1.214, declared in plugin.json) guarantees `fork` is
            # distinguishable from `resume` whenever this event fires at
            # all — no ambiguity-handling needed below that floor.
            decs_v2_clear_session_cache "$SESSION_ID"
            ;;
        *)
            cached=$(decs_v2_read_session_cache "$SESSION_ID")
            if [ -n "$cached" ]; then
                reattach_id=$(printf '%s' "$cached" | jq -r '.decsSessionId // empty' 2>/dev/null)
            fi
            ;;
    esac

    local consumer_id
    consumer_id=$(decs_v2_cached_consumer_id "$V2_SCOPE_ID" 2>/dev/null)
    if [ -z "$consumer_id" ]; then
        local reg_envelope reg_response reg_code reg_body
        reg_envelope=$(jq -n --arg scope "$V2_SCOPE_ID" \
            '{target:{scopeId:$scope}, input:{name:"Claude Code", surface:"cli"}}')
        reg_response=$(decs_v2_call "$host" "register.decs.consumer" "$API_KEY" "$reg_envelope" 8)
        reg_code=$(printf '%s' "$reg_response" | tail -n1)
        reg_body=$(printf '%s' "$reg_response" | sed '$d')
        if [ "$reg_code" = "200" ]; then
            consumer_id=$(printf '%s' "$reg_body" | jq -r '.output.consumerId // empty' 2>/dev/null)
            [ -n "$consumer_id" ] && decs_v2_cache_consumer_id "$V2_SCOPE_ID" "$consumer_id"
        fi
    fi

    if [ -z "$consumer_id" ]; then
        # Could not register or read a cached consumer — no v2 session is
        # possible this turn. Never block SessionStart on a DECS problem.
        [ -n "$LEGACY_ID" ] && run_legacy_fallback
        return 0
    fi

    build_input() {
        local reattach="$1"
        jq -n \
            --arg consumerId "$consumer_id" \
            --arg model "$MODEL" \
            --arg effort "$EFFORT" \
            --arg nativeSessionRef "$CC_SESSION_ID" \
            --arg reattach "$reattach" \
            '{consumerId:$consumerId, provider:"anthropic"}
             | (if $model != "" then .model = $model else . end)
             | (if $effort != "" then .effort = $effort else . end)
             | (if $nativeSessionRef != "" then .nativeSessionRef = $nativeSessionRef else . end)
             | (if $reattach != "" then .decsSessionId = $reattach else . end)'
    }

    local input_json envelope response code body
    input_json=$(build_input "$reattach_id")
    envelope=$(jq -n --arg scope "$V2_SCOPE_ID" --argjson input "$input_json" \
        '{target:{scopeId:$scope}, input:$input}')
    response=$(decs_v2_call "$host" "start.decs.session" "$API_KEY" "$envelope" 8)
    code=$(printf '%s' "$response" | tail -n1)
    body=$(printf '%s' "$response" | sed '$d')

    if [ "$code" != "200" ] && [ -n "$reattach_id" ]; then
        local err_code
        err_code=$(printf '%s' "$body" | jq -r '.error.error // empty' 2>/dev/null)
        if [ "$err_code" = "session_not_found" ]; then
            # Stale cached id (server-side data gone, membership revoked,
            # a different environment) — clear it and mint fresh, once.
            decs_v2_clear_session_cache "$SESSION_ID"
            input_json=$(build_input "")
            envelope=$(jq -n --arg scope "$V2_SCOPE_ID" --argjson input "$input_json" \
                '{target:{scopeId:$scope}, input:$input}')
            response=$(decs_v2_call "$host" "start.decs.session" "$API_KEY" "$envelope" 8)
            code=$(printf '%s' "$response" | tail -n1)
            body=$(printf '%s' "$response" | sed '$d')
        fi
    fi

    if [ "$code" = "200" ]; then
        local decs_session_id context
        decs_session_id=$(printf '%s' "$body" | jq -r '.output.decsSessionId // empty' 2>/dev/null)
        context=$(printf '%s' "$body" | jq -c '.output.context // empty' 2>/dev/null)
        if [ -n "$decs_session_id" ]; then
            decs_v2_write_session_cache "$SESSION_ID" "$V2_SCOPE_ID" "$decs_session_id" "$consumer_id" "$host"
            render_bootstrap_context "$context"
        fi
        return 0
    fi

    local err_code2
    err_code2=$(printf '%s' "$body" | jq -r '.error.error // empty' 2>/dev/null)
    if [ "$err_code2" = "consumer_not_found" ]; then
        # Stale cached consumer — clear so the NEXT SessionStart
        # re-registers; this turn falls back rather than retrying inline
        # (avoid a second round trip on an already-failing turn).
        decs_v2_clear_cached_consumer "$V2_SCOPE_ID"
    fi

    # Any other failure (401/403 credential dead, network/5xx, unexpected
    # shape): fall back to legacy if this file also carries a legacy id,
    # else stay silent. No loud banner here — the Stop hook is where a
    # v2-mode auth failure is surfaced once per session, mirroring v1's
    # AUTH_OK pattern.
    [ -n "$LEGACY_ID" ] && run_legacy_fallback
    return 0
}

if [ -n "$V2_SCOPE_ID" ] && [ -n "$API_KEY" ]; then
    run_v2_bootstrap
elif [ -n "$LEGACY_ID" ]; then
    run_legacy_fallback
fi
# else: no usable identity/credential combination for this directory —
# stay silent by design (see header).
exit 0
