#!/bin/bash
# decs-version: 1.1.1 (relentless-decs-codex plugin)
#
# decs-v2-common.sh — shared helpers for the relentless-decs-codex Codex CLI
# plugin's native v2 hooks (session-start.sh, stop.sh). This is the Codex
# counterpart of decs/plugin/hooks/lib/decs-v2-common.sh (the Claude Code
# plugin's common lib) — same shape, same fail-open discipline, adapted for
# what Codex's hook payloads actually carry (empirically probed against
# codex-cli 0.146.0, not assumed):
#   - no `effort.level` field anywhere in a Codex hook payload (§4.3 of
#     ai-interfacing-proposal.md — confirmed absent in a live SessionStart
#     payload capture, not just "not found in docs")
#   - SessionStart's `source` values are documented as startup/resume/clear/
#     compact ONLY — no `fork`, unlike Claude Code's floor-gated fifth value.
#     Codex has a top-level `codex fork` command but its interactive-only
#     shape (no --json/headless output) made live verification of what
#     `source` it produces impractical from this probe; UNVERIFIED, treated
#     defensively below (see run_v2_bootstrap in session-start.sh).
#
# Pure bash + jq + curl. Fails open throughout: every function that can fail
# returns a non-zero status and an empty/absent result rather than aborting
# the calling hook. No `set -e` (same repo convention as decs/hooks/*.sh and
# the Claude Code plugin's common lib).

# === Repo root + P7-6 identity library ===
#
# Codex plugins installed from a marketplace are copied into
# $CODEX_HOME/plugins/cache/... (empirically confirmed: a local-source
# `codex plugin add` copies the plugin directory into the CODEX_HOME cache,
# not into the git checkout) — files OUTSIDE this plugin's own tree are not
# carried along, exactly the same constraint the Claude Code plugin's common
# lib documents for its own cache. decs/lib/resolve-decs-identity.sh is a
# SIBLING of decs/codex/, not a descendant, so a plugin-relative path cannot
# reach it once installed.
#
# Same fix as the Claude Code plugin (which learned this from its first real
# consumer): the resolver is vendored INSIDE this plugin tree
# (hooks/lib/resolve-decs-identity.sh) as a byte-identical copy of the
# canonical decs/lib/resolve-decs-identity.sh (identical minus the version
# stamp line, enforced by decs/tests/plugin-resolver-vendored-test.sh).
# Preference order: the checkout's own decs/lib copy first (a decs
# development checkout always runs its current committed resolver), then
# the plugin-bundled copy (consumer repos, where only .decs.json exists).
decs_v2_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null
}

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

# === Cross-platform session id (mirrors decs/hooks/*.sh get_session_id and
# the Claude Code plugin's decs_v2_session_id) ===
decs_v2_session_id() {
    local codex_session_id="$1"
    if [ -n "$codex_session_id" ]; then
        echo "$codex_session_id" | tr -cd 'a-zA-Z0-9-' | cut -c1-36
    elif command -v md5sum &>/dev/null; then
        echo "$PWD" | md5sum | cut -c1-12
    else
        echo "$PWD" | md5 | cut -c1-12
    fi
}

# === v2 session cache (keyed by native Codex session_id) ===
# Prefixed "codex" (unlike the Claude Code plugin's decs-v2-session-*.json)
# so the two tools' caches never collide even in the unlikely event a
# session id were ever reused — cheap to keep them namespace-distinct.
decs_v2_session_cache_file() {
    echo "/tmp/decs-v2-codex-session-$1.json"
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
# Lives under $CODEX_HOME (defaulting to ~/.codex, Codex's own per-user data
# dir) — the direct counterpart of the Claude Code plugin's
# ~/.claude/decs-v2-consumer-cache.json.
DECS_V2_CONSUMER_CACHE="${CODEX_HOME:-$HOME/.codex}/decs-v2-consumer-cache.json"

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
# caller passes it so each hook can budget against its own Codex-declared
# timeout. Empirically confirmed (this package's V1 probe, throwaway
# CODEX_HOME + local listener, codex-cli 0.146.0): a Codex hook's outbound
# curl is NOT blocked by `sandbox_workspace_write.network_access` — tested
# true/false/default(read-only), all three let the hook's request through.
# Docs state hook commands "are subject to sandbox restrictions, including
# network_access" in general; that did not hold for network_access
# specifically in this tested configuration. If a future Codex version
# changes this, every call here degrades to a curl timeout — fail-open,
# same as an unreachable host today.
#
# Same curl -w framing decs/hooks/*.sh and the Claude Code plugin use, for
# the same reason (one familiar extraction pattern everywhere):
#   RESPONSE=$(decs_v2_call ...)
#   CODE=$(printf '%s' "$RESPONSE" | tail -n1)
#   BODY=$(printf '%s' "$RESPONSE" | sed '$d')
#
# No x-relentless-surface header — same reasoning as the Claude Code
# plugin's common lib: an API-key-authenticated caller may only additionally
# claim "mcp", so sending anything else here is dead weight; "rest" is the
# correct automatic provenance surface for a hook-mediated REST call.
decs_v2_call() {
    local host="$1" action_key="$2" api_key="$3" envelope_json="$4" max_time="$5"
    curl -s --max-time "$max_time" -w $'\n%{http_code}' \
        -X POST "${host}/api/semantic-actions/${action_key}" \
        -H "Authorization: Bearer ${api_key}" \
        -H "Content-Type: application/json" \
        -d "$envelope_json" 2>/dev/null
}
