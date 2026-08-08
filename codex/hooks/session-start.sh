#!/bin/bash
# decs-version: 1.1.1 (relentless-decs-codex plugin)
#
# DECS v2 — Codex SessionStart hook: session bootstrap.
#
# v2 mode (a v2 project identity resolves for $PWD AND a project-scoped
# credential is configured): register.decs.consumer once per project scope
# (cached), then start.decs.session — minting a new DECS session on
# startup/clear, re-attaching by the CACHED server-issued id on
# resume/compact (never minting on re-attach).
#
# No legacy fallback: unlike the Claude Code plugin, Codex never had a v1
# DECS shell-hook ecosystem to fall back to, so there is nothing to
# delegate to when v2 identity/credential is absent — this hook simply
# stays silent (the §6.1 not-installed offer lives in AGENTS.md, read by
# the agent directly, never a hook banner — same doctrine as the Claude
# Code plugin).
#
# Never blocks. Every network call is bounded (--max-time, inside
# decs_v2_call) well under this hook's declared timeout.
#
# source-value caveat (see decs-v2-common.sh header): Codex's documented
# SessionStart source values are startup/resume/clear/compact — no `fork`
# equivalent is documented, and this package could not verify live what
# `codex fork` produces (the command is interactive-only, no headless/JSON
# path). Any source outside the four documented values — including a
# possible future/undocumented fork signal — falls into the same branch as
# resume/compact below: attempt reattach if something is cached, mint if
# not. This is a DEFENSIVE DEFAULT, not a verified-safe one: if `codex
# fork` reports `source:"resume"` (plausible, since it isn't distinguished
# in the docs), a forked Codex conversation could re-attach to the same
# DECS session as its parent — the same invariant-3 risk the Claude Code
# plugin's 2.1.214 floor exists to rule out there. UNVERIFIED here; flagged
# in decs/codex/README.md rather than silently assumed safe.

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/decs-v2-common.sh
source "$PLUGIN_ROOT/hooks/lib/decs-v2-common.sh"

INPUT=$(cat 2>/dev/null || true)
CODEX_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
MODEL=$(printf '%s' "$INPUT" | jq -r '.model // empty' 2>/dev/null)
SESSION_ID=$(decs_v2_session_id "$CODEX_SESSION_ID")

REPO_ROOT=$(decs_v2_repo_root)
[ -n "$REPO_ROOT" ] || exit 0

if ! decs_v2_source_resolver "$REPO_ROOT"; then
    # Neither the checkout's decs/lib copy nor the plugin-bundled copy of
    # resolve-decs-identity.sh could be sourced — a damaged install.
    exit 0
fi

resolve_decs_identity "$PWD"
V2_SCOPE_ID="$RESOLVE_DECS_V2_SCOPE_ID"
V2_HOST="$RESOLVE_DECS_V2_HOST"
API_KEY="${RELENTLESS_DECS_API_KEY:-}"

# Condensed start hooks (opt-in), identical to the Claude Code plugin's switch
# and reading the same variable. Codex's `additionalContext` budget is ~2500
# tokens — smaller than Claude Code's 10k-character persistence threshold — so
# this is where it most often earns its keep. It is still OFF by default:
# diverging the default per client would mean the same project told two agents
# two different things about itself, and the server's own degradation ladder
# already trims a large bootstrap rather than dropping it.
case "${RELENTLESS_DECS_CONDENSED_START:-}" in
    1 | true | TRUE | yes | on) CONDENSED=1 ;;
    *) CONDENSED=0 ;;
esac

[ -n "$V2_SCOPE_ID" ] && [ -n "$API_KEY" ] || exit 0

# Terser than the Claude Code plugin's renderer, for the budget reason above:
# one line per field rather than headed sections, and no closing guidance
# beyond the two actions. The node id is on every decision either way — that is
# what makes a reference expandable through list_decs_decision.
DECISION_JQ='
def field($label; $v): if ($v // "") == "" then empty else "  \($label): \($v)" end;
def render:
  "- \(.title) `\(.decisionNodeId)`",
  (if (.what // null) == null then
     empty
   else
     field("What"; .what), field("Why"; .why),
     field("Purpose"; .purpose), field("Constraints"; .constraints),
     (if .bodyTruncated then "  (clamped — list_decs_decision reads it whole)" else empty end)
   end);
'

render_bootstrap_context() {
    local context="$1"
    [ -n "$context" ] && [ "$context" != "null" ] || return 0

    local text
    text=$(printf '%s' "$context" | jq -r "$DECISION_JQ"'
        (if ((.keyDecisions.recent // []) | length) > 0 then
            "Key decisions (\(.keyDecisions.count)):",
            ((.keyDecisions.recent // [])[] | render)
         elif (.keyDecisions.count // 0) > 0 then
            "Key decisions: \(.keyDecisions.count) — read with list_decs_decision"
         else empty end),
        (if ((.recentDecisions.recent // []) | length) > 0 then
            "Recent decisions (\(.recentDecisions.count) in total):",
            ((.recentDecisions.recent // [])[] | render)
         elif (.recentDecisions.count // 0) > 0 then
            "Other decisions on file: \(.recentDecisions.count) — read with list_decs_decision"
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
            "(bootstrap trimmed: " + ((.truncated) | join(", ")) +
            " — still readable through list_decs_decision)"
         else empty end)
    ' 2>/dev/null)

    local title
    title=$(printf '%s' "$context" | jq -r '.project.title // "this project"' 2>/dev/null)

    [ -n "$text" ] || text="No decisions or open questions recorded yet."

    local full="=== DECS v2: ${title} ===
${text}
Record decisions via the MCP tool add_decs_decision — never a raw curl
typed by hand, see decs/README.md. Read more with list_decs_decision,
list_decs_plan and list_decs_project. Ask via add_decs_question; answers
surface automatically in this session's awareness. If you asked badly or the
question stopped mattering, update_decs_question corrects or retires it —
never leave a dead question sitting in a human's queue."

    jq -n --arg ctx "$full" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'
}

host="${V2_HOST:-https://www.relentless.build}"
reattach_id=""
cached=""

case "$SOURCE" in
    startup|clear)
        decs_v2_clear_session_cache "$SESSION_ID"
        ;;
    *)
        # resume|compact, and (defensively, see header) any other/unknown
        # source value including a possible future fork signal.
        cached=$(decs_v2_read_session_cache "$SESSION_ID")
        if [ -n "$cached" ]; then
            reattach_id=$(printf '%s' "$cached" | jq -r '.decsSessionId // empty' 2>/dev/null)
        fi
        ;;
esac

consumer_id=$(decs_v2_cached_consumer_id "$V2_SCOPE_ID" 2>/dev/null)
if [ -z "$consumer_id" ]; then
    reg_envelope=$(jq -n --arg scope "$V2_SCOPE_ID" \
        '{target:{scopeId:$scope}, input:{name:"Codex", surface:"cli"}}')
    reg_response=$(decs_v2_call "$host" "register.decs.consumer" "$API_KEY" "$reg_envelope" 8)
    reg_code=$(printf '%s' "$reg_response" | tail -n1)
    reg_body=$(printf '%s' "$reg_response" | sed '$d')
    if [ "$reg_code" = "200" ]; then
        consumer_id=$(printf '%s' "$reg_body" | jq -r '.output.consumerId // empty' 2>/dev/null)
        [ -n "$consumer_id" ] && decs_v2_cache_consumer_id "$V2_SCOPE_ID" "$consumer_id"
    fi
fi

# Could not register or read a cached consumer — no v2 session possible
# this turn. Never block SessionStart on a DECS problem.
[ -n "$consumer_id" ] || exit 0

build_input() {
    local reattach="$1"
    jq -n \
        --arg consumerId "$consumer_id" \
        --arg model "$MODEL" \
        --arg nativeSessionRef "$CODEX_SESSION_ID" \
        --arg reattach "$reattach" \
        --argjson condensed "$CONDENSED" \
        '{consumerId:$consumerId, provider:"openai"}
         | (if $model != "" then .model = $model else . end)
         | (if $nativeSessionRef != "" then .nativeSessionRef = $nativeSessionRef else . end)
         | (if $reattach != "" then .decsSessionId = $reattach else . end)
         # Sent only when asked for: a server older than this plugin has a
         # `.strict()` input schema and would refuse an unknown key, and the
         # field'"'"'s absence already means false.
         | (if $condensed == 1 then .condensed = true else . end)'
    # No `effort` field: Codex hook payloads carry no reasoning-effort
    # equivalent (§4.3, live-confirmed absent). Omitted rather than
    # guessed — provenance display tolerates absence.
}

input_json=$(build_input "$reattach_id")
envelope=$(jq -n --arg scope "$V2_SCOPE_ID" --argjson input "$input_json" \
    '{target:{scopeId:$scope}, input:$input}')
response=$(decs_v2_call "$host" "start.decs.session" "$API_KEY" "$envelope" 8)
code=$(printf '%s' "$response" | tail -n1)
body=$(printf '%s' "$response" | sed '$d')

if [ "$code" != "200" ] && [ -n "$reattach_id" ]; then
    err_code=$(printf '%s' "$body" | jq -r '.error.error // empty' 2>/dev/null)
    if [ "$err_code" = "session_not_found" ]; then
        # Stale cached id — clear it and mint fresh, once.
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
    decs_session_id=$(printf '%s' "$body" | jq -r '.output.decsSessionId // empty' 2>/dev/null)
    context=$(printf '%s' "$body" | jq -c '.output.context // empty' 2>/dev/null)
    if [ -n "$decs_session_id" ]; then
        decs_v2_write_session_cache "$SESSION_ID" "$V2_SCOPE_ID" "$decs_session_id" "$consumer_id" "$host"
        render_bootstrap_context "$context"
    fi
    exit 0
fi

err_code2=$(printf '%s' "$body" | jq -r '.error.error // empty' 2>/dev/null)
if [ "$err_code2" = "consumer_not_found" ]; then
    # Stale cached consumer — clear so the NEXT SessionStart re-registers.
    decs_v2_clear_cached_consumer "$V2_SCOPE_ID"
fi

# Any other failure (401/403 credential dead, network/5xx, unexpected
# shape): stay silent this turn — the Stop hook is where a v2-mode auth
# failure is surfaced once per session.
exit 0
