#!/bin/bash
# decs-version: 1.1.0 (relentless-decs plugin)
#
# decs-v2-common.sh — shared helpers for the relentless-decs Claude Code
# plugin's native v2 hooks (session-start.sh, user-prompt-submit.sh,
# stop.sh). Sourced via ${CLAUDE_PLUGIN_ROOT}/hooks/lib/decs-v2-common.sh —
# safe because this file lives INSIDE the plugin directory and travels with
# it into the plugin cache on install, as does its sibling
# resolve-decs-identity.sh (the vendored identity library — see
# decs_v2_source_resolver() below for how the two copies relate).
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
# a descendant of it, so a ${CLAUDE_PLUGIN_ROOT}-relative path could not
# reach it once the plugin is installed from the marketplace — and through
# v1.0.4 that meant CONSUMER repos (a .decs.json, no vendored decs/ tree)
# silently resolved nothing: no v2 session, no bootstrap, no hygiene, while
# the MCP half kept working. Reported live by the first real consumer.
#
# So the resolver is now vendored INSIDE the plugin tree
# (hooks/lib/resolve-decs-identity.sh) as a byte-identical copy of the
# canonical decs/lib/resolve-decs-identity.sh (identical minus the version
# stamp line, enforced by decs/tests/plugin-resolver-vendored-test.sh — the
# drift risk that previously argued against vendoring is answered by that
# test, not by leaving consumers broken). Preference order in
# decs_v2_source_resolver: the CHECKOUT's own decs/lib copy first (a decs
# development checkout always runs its current committed resolver, even
# ahead of a plugin release), then the plugin-bundled copy (every consumer
# repo, where only .decs.json exists).
decs_v2_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Sources resolve-decs-identity.sh into the CALLER's shell (this function
# must be called with `source`'d effect, i.e. plain invocation — not in a
# subshell — so resolve_decs_identity() and its RESOLVE_DECS_* globals
# become available to the caller). Repo-vendored copy first, plugin-bundled
# copy second (see header). Returns 1 (fails open) only when neither
# exists — which means a damaged plugin install.
decs_v2_source_resolver() {
    local repo_root="$1"
    local lib=""
    if [ -n "$repo_root" ] && [ -f "$repo_root/decs/lib/resolve-decs-identity.sh" ]; then
        lib="$repo_root/decs/lib/resolve-decs-identity.sh"
    elif [ -f "$(dirname "${BASH_SOURCE[0]}")/resolve-decs-identity.sh" ]; then
        lib="$(dirname "${BASH_SOURCE[0]}")/resolve-decs-identity.sh"
    fi
    [ -n "$lib" ] || return 1
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
