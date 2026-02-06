#!/bin/bash
# DECS Stop Hook: Block and inject decision hygiene check
# Uses block+reason so Claude sees the instruction and continues

# === CONFIG ===
DECS_CONFIG="$HOME/.claude/decs-config.json"

API_KEY=""
BASE_URL=""
BUILDSPACE_ID=""
if [ -f "$DECS_CONFIG" ]; then
    API_KEY=$(jq -r '.relentlessApiKey // empty' "$DECS_CONFIG")
    BASE_URL=$(jq -r '.relentlessUrl // empty' "$DECS_CONFIG")
    BUILDSPACE_ID=$(jq -r '.buildspaceId // empty' "$DECS_CONFIG")
fi

# Cross-platform session ID
get_session_id() {
    if command -v md5sum &>/dev/null; then
        echo "$PWD" | md5sum | cut -c1-12
    else
        echo "$PWD" | md5 | cut -c1-12
    fi
}

SESSION_ID=$(get_session_id)
SESSION_MARKER="/tmp/decs-session-triggered-${SESSION_ID}"
HYGIENE_DONE="/tmp/decs-hygiene-done-${SESSION_ID}"

# If hygiene already done this session, allow stop
if [ -f "$HYGIENE_DONE" ]; then
    rm -f "$HYGIENE_DONE"
    exit 0
fi

# Check if in DECS-enabled repo
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
SPACE_ID=""
if [ -n "$CONFIG_FILE" ]; then
    SPACE_ID=$(jq -r '.relentlessSpaceId // empty' "$CONFIG_FILE" 2>/dev/null)
fi

HAS_DECS_CONFIG=$( [ -n "$SPACE_ID" ] && echo "true" || echo "false" )
HAS_SESSION_MARKER=$( [ -f "$SESSION_MARKER" ] && echo "true" || echo "false" )

# If neither condition met, allow stop
if [ "$HAS_DECS_CONFIG" = "false" ] && [ "$HAS_SESSION_MARKER" = "false" ]; then
    exit 0
fi

# Clean up session marker, set hygiene-done flag
rm -f "$SESSION_MARKER"
touch "$HYGIENE_DONE"

# Build the reason message
REASON="DECS Decision Hygiene Check: Before ending, review this session for decisions worth documenting. WHAT TO DOCUMENT: 1) Technology choices, API design, architectural patterns, 2) Meaningful insights about how this system works or should work, 3) Context future sessions need to maintain coherence, 4) Discovered constraints that affect future work, 5) Reversals or updates to prior decisions. HOW TO CREATE: POST to ${BASE_URL}/api/nodes?buildspaceId=${BUILDSPACE_ID} with header 'Authorization: Bearer <key>' from ~/.claude/decs-config.json (relentlessApiKey field). Body: {\"kind\": \"decision\", \"title\": \"<concise title>\", \"content\": {\"what\": \"...\", \"why\": \"...\", \"purpose\": \"...\", \"constraints\": \"...\", \"isKeyDecision\": false}, \"parentId\": \"${SPACE_ID}\"}. KEY DECISIONS: Set isKeyDecision to true only for foundational choices that all future sessions must see. Use sparingly — only for load-bearing architectural choices. If existing decisions evolved this session, update them via PATCH ${BASE_URL}/api/nodes/<id>?buildspaceId=${BUILDSPACE_ID}. If nothing to document, say 'No new decisions' and stop."

# Block and inject hygiene check
jq -n --arg reason "$REASON" '{"decision": "block", "reason": $reason}'
