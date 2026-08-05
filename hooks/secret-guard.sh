#!/bin/bash
# decs-version: 1.0.4 (relentless-decs plugin)
# DECS Secret Guard — PreToolUse caution-and-confirm for a raw curl/wget
# that appears to carry a DECS credential (RR-4, docs/decs-v2/phase7-packages.md).
#
# This is the PLUGIN-SHIPPED COPY of decs/hooks/decs-secret-guard.sh (P7-1),
# forked here because a PreToolUse hook entry cannot be shipped
# present-but-disabled in a Claude Code plugin manifest (hooks declared in a
# plugin's hooks.json are always active the moment the plugin is enabled —
# there is no supported "enabled: false" on a hook entry, verified against
# current plugin docs). RR-4 requires this hook to be OPT-IN, DEFAULT OFF —
# so it deliberately does NOT appear in decs/plugin/hooks/hooks.json. The
# script ships inside the plugin (this file) so the manual opt-in path in
# decs/README.md has something real to point at once the plugin is
# installed; see that doc's "Secret guard (opt-in)" section for the exact
# settings.json snippet a user pastes into their OWN settings to turn it on.
#
# Behavior is unchanged from the P7-1 original: caution-and-confirm, not a
# hard deny. The first occurrence of a matching command is denied with a
# reason asking the model to review it for secrets; an identical re-send of
# the exact same command passes through. Non-recursive by construction — the
# confirmation marker is keyed on a hash of the exact command text plus the
# session id, so the same command can only ever be a "first occurrence" once
# per session, and two concurrent sessions never share a confirmation.
#
# Triggers ONLY when ALL of the following hold: the tool call is Bash; the
# command contains a raw "curl" or "wget" (a word, not a substring of some
# other token — invoking decs-record.sh or an MCP tool call never matches);
# the command targets the DECS host; and the command text carries what
# looks like an rlnt_-prefixed credential literal. This format-based check
# catches BOTH the legacy DECS-class key and a v2 project-scoped credential
# unmodified — both share the rlnt_ prefix and both travel to the same
# host. Never prints any part of the detected token or the command itself
# in the reason text. Fails open (exit 0, no decision) on any parsing
# ambiguity — a hook that denies incorrectly on malformed input is worse
# than one that occasionally lets a real secret through for the model to
# review on a first pass.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$COMMAND" ] || exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# No session_id to key the marker on — ambiguous, fail open rather than guess
# (a marker not keyed per-session could let one window's confirmation apply
# to another's identical command).
[ -n "$SESSION_ID" ] || exit 0

# Raw curl or wget, matched as a whole word so "curly", "libcurl-dev", or a
# path ending in "curl-wrapper.sh" don't match, and so decs-record.sh's own
# invocation (which names neither word) never does either.
echo "$COMMAND" | grep -qwE 'curl|wget' || exit 0

# Aimed at the DECS host. Default to matching the bare relentless.build
# domain (covers www and any other subdomain); prefer a configured host
# verbatim if either the legacy decs-config.json or the v2
# RELENTLESS_DECS_HOST env var points somewhere else entirely (a future
# self-hosted deployment). v2 checked first since it is the credential
# format this hook is most likely guarding in a plugin-installed
# environment; legacy checked as a fallback for repos still on v1-only
# setup.
DECS_HOST_MATCH="relentless.build"
CONFIGURED_HOST=""
if [ -n "${RELENTLESS_DECS_HOST:-}" ]; then
    CONFIGURED_HOST=$(echo "$RELENTLESS_DECS_HOST" | sed -E 's#^[a-zA-Z]+://##; s#/.*##')
elif [ -f "$HOME/.claude/decs-config.json" ]; then
    BASE_URL=$(jq -r '.relentlessUrl // empty' "$HOME/.claude/decs-config.json" 2>/dev/null)
    CONFIGURED_HOST=$(echo "$BASE_URL" | sed -E 's#^[a-zA-Z]+://##; s#/.*##')
fi
case "$CONFIGURED_HOST" in
    *relentless.build) ;; # already covered by the default
    "") ;;                # no config either way — keep the default
    *) DECS_HOST_MATCH="$CONFIGURED_HOST" ;;
esac
echo "$COMMAND" | grep -qF "$DECS_HOST_MATCH" || exit 0

# Carries what looks like a DECS credential literal — v1 and v2 alike share
# this prefix.
echo "$COMMAND" | grep -qE 'rlnt_[A-Za-z0-9_-]+' || exit 0

# === Hash the exact command text (cross-platform) to key the marker ===
hash_command() {
    if command -v sha256sum &>/dev/null; then
        printf '%s' "$1" | sha256sum | cut -c1-16
    elif command -v shasum &>/dev/null; then
        printf '%s' "$1" | shasum -a 256 | cut -c1-16
    elif command -v md5sum &>/dev/null; then
        printf '%s' "$1" | md5sum | cut -c1-16
    else
        printf '%s' "$1" | md5 | cut -c1-16
    fi
}

CMD_HASH=$(hash_command "$COMMAND")
SAFE_SESSION=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-' | cut -c1-36)
MARKER_FILE="/tmp/decs-secretguard-${SAFE_SESSION}-${CMD_HASH}"

if [ -f "$MARKER_FILE" ]; then
    # Identical re-send within this session: pass through, no decision output.
    exit 0
fi

# First occurrence: deny with a review reason and record the marker so an
# identical re-send passes next time. Never echo any part of the command or
# the detected token.
touch "$MARKER_FILE"
REASON="This command looks like a raw curl or wget carrying a Relentless/DECS credential directly in the command text. Review it for secrets before re-sending: prefer the MCP tool add_decs_decision / add_decs_question (v2) or the decs-record.sh helper (v1 legacy) — either reads the key itself so it never appears in this transcript. If a raw request to this host is genuinely intended, re-send the exact same command once more and it will go through."
jq -n --arg reason "$REASON" '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": $reason}}'
