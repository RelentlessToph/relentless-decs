#!/bin/bash
# DECS Context Injection Hook
# Runs on UserPromptSubmit — adds decisions as context when "decision" or "decs" is mentioned

# === CONFIG ===
DECS_CONFIG="$HOME/.claude/decs-config.json"

if [ ! -f "$DECS_CONFIG" ]; then
    exit 0
fi

API_KEY=$(jq -r '.relentlessApiKey // empty' "$DECS_CONFIG")
BASE_URL=$(jq -r '.relentlessUrl // empty' "$DECS_CONFIG")
BUILDSPACE_ID=$(jq -r '.buildspaceId // empty' "$DECS_CONFIG")

if [ -z "$API_KEY" ] || [ -z "$BASE_URL" ] || [ -z "$BUILDSPACE_ID" ]; then
    exit 0
fi

CACHE_TTL=300  # 5 minutes

# === CROSS-PLATFORM HELPERS ===
get_session_id() {
    if command -v md5sum &>/dev/null; then
        echo "$PWD" | md5sum | cut -c1-12
    else
        echo "$PWD" | md5 | cut -c1-12
    fi
}

get_file_mtime() {
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f %m "$file"
    else
        stat -c %Y "$file"
    fi
}

# === GATEKEEPER ===

# Read prompt from stdin (JSON input)
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

# Check: Does prompt contain trigger keyword?
if ! echo "$PROMPT" | grep -qiE "(decision|decs|architectural)"; then
    exit 0
fi

# Check: Does .decs.json exist in repo?
find_decs_config() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.decs.json" ]; then
            echo "$dir/.decs.json"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

CONFIG_FILE=$(find_decs_config)
if [ -z "$CONFIG_FILE" ]; then
    exit 0
fi

SPACE_ID=$(jq -r '.relentlessSpaceId // empty' "$CONFIG_FILE")
if [ -z "$SPACE_ID" ]; then
    exit 0
fi

# === CREATE SESSION MARKER ===
SESSION_ID=$(get_session_id)
MARKER_FILE="/tmp/decs-session-triggered-${SESSION_ID}"
touch "$MARKER_FILE"

# === FETCH & CACHE ===

CACHE_FILE="/tmp/decs-relentless-cache-${SPACE_ID}.json"

CACHE_VALID=false
if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(($(date +%s) - $(get_file_mtime "$CACHE_FILE")))
    if [ "$CACHE_AGE" -lt "$CACHE_TTL" ]; then
        CACHE_VALID=true
    fi
fi

if [ "$CACHE_VALID" = false ]; then
    RESPONSE=$(curl -s "${BASE_URL}/api/nodes?parentId=${SPACE_ID}&kind=decision&buildspaceId=${BUILDSPACE_ID}" \
      -H "Authorization: Bearer ${API_KEY}")
    echo "$RESPONSE" > "$CACHE_FILE"
fi

DECISIONS=$(cat "$CACHE_FILE")
DECISION_COUNT=$(echo "$DECISIONS" | jq 'length' 2>/dev/null)

if [ -z "$DECISION_COUNT" ] || [ "$DECISION_COUNT" -eq 0 ]; then
    exit 0
fi

# === OUTPUT ===

echo "=== DECS: Architectural Decisions ==="
echo

KEY_DECISIONS=$(echo "$DECISIONS" | jq '[.[] | select(.content.isKeyDecision == true)]')
RECENT_DECISIONS=$(echo "$DECISIONS" | jq '[.[] | select(.content.isKeyDecision != true)] | .[0:10]')

key_count=$(echo "$KEY_DECISIONS" | jq 'length')
recent_count=$(echo "$RECENT_DECISIONS" | jq 'length')

if [ "$key_count" -gt 0 ]; then
    echo "### Key Decisions (always active)"
    echo
    echo "$KEY_DECISIONS" | jq -r '.[] | "## \(.title)\n**What:** \(.content.what // "—")\n**Why:** \(.content.why // "—")\n**Purpose:** \(.content.purpose // "—")\n**Constraints:** \(.content.constraints // "—")\n---\n"'
fi

if [ "$recent_count" -gt 0 ]; then
    echo "### Recent Decisions"
    echo
    echo "$RECENT_DECISIONS" | jq -r '.[] | "## \(.title)\n**What:** \(.content.what // "—")\n**Why:** \(.content.why // "—")\n**Purpose:** \(.content.purpose // "—")\n**Constraints:** \(.content.constraints // "—")\n---\n"'
fi

echo
echo "Consider these decisions when responding. Flag any contradictions."
