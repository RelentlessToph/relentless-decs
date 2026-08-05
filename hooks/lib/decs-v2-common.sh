#!/bin/bash
# decs-version: 1.0.3 (relentless-decs plugin)
#
# decs-v2-common.sh — shared helpers for the relentless-decs Claude Code
# plugin's native v2 hooks (session-start.sh, user-prompt-submit.sh,
# stop.sh). Sourced via ${CLAUDE_PLUGIN_ROOT}/hooks/lib/decs-v2-common.sh —
# safe because this file lives INSIDE the plugin directory and travels with
# it into the plugin cache on install (unlike decs/lib/resolve-decs-identity.sh,
# which lives OUTSIDE decs/plugin/ and is reached a different way — see
# decs_v2_repo_root() below).
#
# Pure bash + jq + curl. Fails open throughout: every function that can fail
# returns a non-zero status and an empty/absent result rather than aborting
# the calling hook. No `set -e` (repo convention, decs/hooks/*.sh) — a hook
# that dies on an unexpected non-zero exits the whole session-critical path
# instead of degrading gracefully.

# === Repo root + P7-6 identity library ===
#
# Claude Code plugins installed from a marketplace are copied into a cache
# directory, and files OUTSIDE the plugin's own tree are not carried along
# (installed plugins cannot reference paths that traverse out of their own
# root). decs/lib/resolve-decs-identity.sh is a SIBLING of decs/plugin/, not
# a descendant of it, so a ${CLAUDE_PLUGIN_ROOT}-relative path cannot reach
# it once the plugin is installed from the marketplace.
#
# The fix is not to vendor a copy inside decs/plugin/ — that would drift
# from the real P7-6 library the moment either side changed, exactly the
# class of bug the identity library's own header exists to prevent ("never
# reimplement the walk"). Instead: these hooks only do anything useful
# inside a checkout of a repo that has vendored the decs/ toolkit (today,
# only this repo), so they find THAT checkout's own repo root via git and
# source ITS decs/lib/resolve-decs-identity.sh — the real, current,
# committed copy, every time. A repo with no decs/lib (or no git checkout
# at all) yields no repo root here, every v2-mode function below fails
# open, and the calling hook falls through to silence or to its legacy
# fallback exactly as if no .decs.json existed.
decs_v2_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Sources decs/lib/resolve-decs-identity.sh from the given repo root into
# the CALLER's shell (this function must be called with `source`'d effect,
# i.e. plain invocation — not in a subshell — so resolve_decs_identity()
# and its RESOLVE_DECS_* globals become available to the caller).
# Returns 1 (fails open) if the repo root is empty or the library is absent.
decs_v2_source_resolver() {
    local repo_root="$1"
    [ -n "$repo_root" ] || return 1
    local lib="$repo_root/decs/lib/resolve-decs-identity.sh"
    [ -f "$lib" ] || return 1
    # shellcheck source=/dev/null
    source "$lib"
    return 0
}

# === Cross-platform session id (mirrors decs/hooks/*.sh get_session_id) ===
decs_v2_session_id() {
    local cc_session_id="$1"
    if [ -n "$cc_session_id" ]; then
        echo "$cc_session_id" | tr -cd 'a-zA-Z0-9-' | cut -c1-36
    elif command -v md5sum &>/dev/null; then
        echo "$PWD" | md5sum | cut -c1-12
    else
        echo "$PWD" | md5 | cut -c1-12
    fi
}

# === v2 session cache (keyed by native CC session_id) ===
# One JSON file per native session, holding what THIS session needs across
# its three hooks: the resolved project scope, the server-issued DECS
# session id, the consumer id used to mint it, and the resolved host.
# /tmp, matching decs/hooks/*.sh's existing marker-file convention (P7-1's
# manual matrix already proves this pattern works per-session, concurrently,
# across windows, keyed on the real session_id rather than a PWD hash).
decs_v2_session_cache_file() {
    echo "/tmp/decs-v2-session-$1.json"
}

decs_v2_read_session_cache() {
    local file
    file=$(decs_v2_session_cache_file "$1")
    [ -f "$file" ] && cat "$file"
}

decs_v2_write_session_cache() {
    local session_id="$1" project_scope_id="$2" decs_session_id="$3" consumer_id="$4" host="$5"
    local file
    file=$(decs_v2_session_cache_file "$session_id")
    jq -n --arg scope "$project_scope_id" --arg decsSession "$decs_session_id" \
        --arg consumer "$consumer_id" --arg host "$host" \
        '{projectScopeId:$scope, decsSessionId:$decsSession, consumerId:$consumer, host:$host}' \
        > "$file" 2>/dev/null
}

decs_v2_clear_session_cache() {
    rm -f "$(decs_v2_session_cache_file "$1")"
}

# === Consumer cache (per project scope, survives across sessions) ===
# register.decs.consumer is idempotent server-side (ON CONFLICT convergence
# on scope+user+lower(name)), so calling it every SessionStart would be
# SAFE, but this cache avoids paying a network round trip on every session
# just to learn the same consumerId back.
DECS_V2_CONSUMER_CACHE="$HOME/.claude/decs-v2-consumer-cache.json"

decs_v2_cached_consumer_id() {
    local project_scope_id="$1"
    [ -f "$DECS_V2_CONSUMER_CACHE" ] || return 1
    jq -r --arg scope "$project_scope_id" '.[$scope].consumerId // empty' "$DECS_V2_CONSUMER_CACHE" 2>/dev/null
}

decs_v2_cache_consumer_id() {
    local project_scope_id="$1" consumer_id="$2"
    local existing="{}"
    if [ -f "$DECS_V2_CONSUMER_CACHE" ]; then
        existing=$(cat "$DECS_V2_CONSUMER_CACHE" 2>/dev/null)
        [ -n "$existing" ] || existing="{}"
    fi
    mkdir -p "$(dirname "$DECS_V2_CONSUMER_CACHE")" 2>/dev/null
    printf '%s' "$existing" \
        | jq --arg scope "$project_scope_id" --arg consumer "$consumer_id" \
            'if type=="object" then . else {} end | .[$scope] = {consumerId:$consumer}' \
            > "${DECS_V2_CONSUMER_CACHE}.tmp" 2>/dev/null \
        && mv "${DECS_V2_CONSUMER_CACHE}.tmp" "$DECS_V2_CONSUMER_CACHE"
}

decs_v2_clear_cached_consumer() {
    local project_scope_id="$1"
    [ -f "$DECS_V2_CONSUMER_CACHE" ] || return 0
    jq --arg scope "$project_scope_id" 'del(.[$scope])' "$DECS_V2_CONSUMER_CACHE" \
        > "${DECS_V2_CONSUMER_CACHE}.tmp" 2>/dev/null \
        && mv "${DECS_V2_CONSUMER_CACHE}.tmp" "$DECS_V2_CONSUMER_CACHE"
}

# === The one semantic-action HTTP call every v2 hook makes ===
#
# POST {host}/api/semantic-actions/{actionKey} with the project-scoped
# credential. --max-time is REQUIRED on every call (standing rule); the
# caller passes it so each hook can budget against its own CC-declared
# timeout (SessionStart/UserPromptSubmit 10s, Stop 5s).
#
# Prints curl's `-w $'\n%{http_code}'` framing verbatim to stdout (body,
# then a trailing line with the HTTP status) — the SAME shape
# decs/hooks/*.sh already uses inline, so every caller extracts it the same
# familiar way:
#   RESPONSE=$(decs_v2_call ...)
#   CODE=$(printf '%s' "$RESPONSE" | tail -n1)
#   BODY=$(printf '%s' "$RESPONSE" | sed '$d')
#
# No x-relentless-surface header: an API-key-authenticated caller may only
# additionally claim "mcp" (anything else, including a truthful "cli",
# resolves to the same "rest" default the header's absence already
# produces — see route.ts's resolveSurface), so sending it here would be
# dead weight. These are hook-mediated REST calls; "rest" is the correct
# and automatic provenance surface for them.
decs_v2_call() {
    local host="$1" action_key="$2" api_key="$3" envelope_json="$4" max_time="$5"
    curl -s --max-time "$max_time" -w $'\n%{http_code}' \
        -X POST "${host}/api/semantic-actions/${action_key}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "$envelope_json" 2>/dev/null
}
