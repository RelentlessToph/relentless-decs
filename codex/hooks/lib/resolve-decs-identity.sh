#!/bin/bash
# decs-version: 1.1.1 (relentless-decs-codex plugin — vendored copy of decs/lib/resolve-decs-identity.sh, identical minus this line; pinned by decs/tests/plugin-resolver-vendored-test.sh)
#
# resolve-decs-identity.sh — v2 dual-resolution library for .decs.json.
#
# Meant to be SOURCED by future plugin hooks:
#   source "$(dirname "$0")/../lib/resolve-decs-identity.sh"
#   resolve_decs_identity "$PWD"
#   echo "$RESOLVE_DECS_MODE $RESOLVE_DECS_V2_SCOPE_ID"
#
# Can also be run directly for manual checks / the test script, in which
# case it prints the resolved identity as JSON on stdout:
#   decs/lib/resolve-decs-identity.sh /path/to/start/dir
#
# Full rule, with justification: docs/decs-v2/p7-6-resolution.md
#
# Pure bash + jq. No network. Fails open on parse errors (matches the
# existing hooks' discipline in decs/hooks/*.sh — a malformed file never
# halts resolution, it is treated as absent and the walk continues up).

# === resolve_decs_identity <start-dir> ===
# Sets (unsets first, so a stale caller value never leaks through):
#   RESOLVE_DECS_FILE          - path to the resolved .decs.json, or empty
#   RESOLVE_DECS_LEGACY_ID     - relentlessSpaceId, or empty
#   RESOLVE_DECS_V2_SCOPE_ID   - v2.projectScopeId, or empty
#   RESOLVE_DECS_V2_HOST       - v2.host, or empty
#   RESOLVE_DECS_MODE          - v2 | legacy | v2-pending | empty | none
#   RESOLVE_DECS_MALFORMED     - space-separated paths skipped as unparseable
resolve_decs_identity() {
    local start_dir="${1:-$PWD}"
    local dir="$start_dir"
    local found_file=""
    local malformed=()

    RESOLVE_DECS_FILE=""
    RESOLVE_DECS_LEGACY_ID=""
    RESOLVE_DECS_V2_SCOPE_ID=""
    RESOLVE_DECS_V2_HOST=""
    RESOLVE_DECS_MODE="none"
    RESOLVE_DECS_MALFORMED=""

    # Nearest-first walk: stop at the FIRST well-formed .decs.json. A
    # malformed file at a given level is skipped (fail-open) and the walk
    # continues to that level's parent — it is treated as though it were
    # absent, not as a hard stop. A well-formed file, even one with no
    # currently-actionable identity inside it (see v2-pending below), DOES
    # stop the walk: this directory's declared identity is what it is, and
    # silently falling through to an ancestor's DIFFERENT identity would
    # misattribute this directory's decisions. See rule doc §4.
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        local candidate="$dir/.decs.json"
        if [ -f "$candidate" ]; then
            if jq empty "$candidate" >/dev/null 2>&1; then
                found_file="$candidate"
                break
            else
                malformed+=("$candidate")
            fi
        fi
        dir=$(dirname "$dir")
    done

    if [ ${#malformed[@]} -gt 0 ]; then
        RESOLVE_DECS_MALFORMED="${malformed[*]}"
    fi

    if [ -z "$found_file" ]; then
        RESOLVE_DECS_MODE="none"
        return 0
    fi

    RESOLVE_DECS_FILE="$found_file"

    local legacy v2_present v2_scope v2_host
    legacy=$(jq -r '.relentlessSpaceId // empty' "$found_file" 2>/dev/null)
    v2_present=$(jq -r 'has("v2")' "$found_file" 2>/dev/null)
    # `// empty` treats jq's `null` the same as an absent key, which is
    # exactly the "declared but not yet resolvable" case for
    # v2.projectScopeId (RR-2a: production project scope ids do not exist
    # until rollout).
    v2_scope=$(jq -r '.v2.projectScopeId // empty' "$found_file" 2>/dev/null)
    v2_host=$(jq -r '.v2.host // empty' "$found_file" 2>/dev/null)

    RESOLVE_DECS_LEGACY_ID="$legacy"
    RESOLVE_DECS_V2_SCOPE_ID="$v2_scope"
    RESOLVE_DECS_V2_HOST="$v2_host"

    # Rule #1: v2 is preferred over legacy, but ONLY when its
    # projectScopeId is non-null/present. Otherwise legacy, if present.
    if [ -n "$v2_scope" ]; then
        RESOLVE_DECS_MODE="v2"
    elif [ -n "$legacy" ]; then
        RESOLVE_DECS_MODE="legacy"
    elif [ "$v2_present" = "true" ]; then
        RESOLVE_DECS_MODE="v2-pending"
    else
        RESOLVE_DECS_MODE="empty"
    fi

    return 0
}

# === CLI entry point (only when executed directly, not when sourced) ===
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    resolve_decs_identity "${1:-$PWD}"

    malformed_json="[]"
    if [ -n "$RESOLVE_DECS_MALFORMED" ]; then
        malformed_json=$(printf '%s\n' $RESOLVE_DECS_MALFORMED | jq -R . | jq -s .)
    fi

    jq -n \
        --arg file "$RESOLVE_DECS_FILE" \
        --arg legacy "$RESOLVE_DECS_LEGACY_ID" \
        --arg v2scope "$RESOLVE_DECS_V2_SCOPE_ID" \
        --arg v2host "$RESOLVE_DECS_V2_HOST" \
        --arg mode "$RESOLVE_DECS_MODE" \
        --argjson malformed "$malformed_json" \
        '{
            resolvedFile: (if $file == "" then null else $file end),
            legacySpaceId: (if $legacy == "" then null else $legacy end),
            v2ProjectScopeId: (if $v2scope == "" then null else $v2scope end),
            v2Host: (if $v2host == "" then null else $v2host end),
            resolutionMode: $mode,
            malformedSkipped: $malformed
        }'
fi
