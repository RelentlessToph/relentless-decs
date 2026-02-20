#!/bin/bash
# DECS: Get decisions from Relentless for Claude context injection
# Runs on SessionStart — queries decision nodes in the repo's Decisions space
# Uses DECS-scoped API key (restricted to decision + decs node kinds)

# === CONFIG ===
DECS_CONFIG="$HOME/.claude/decs-config.json"

if [ ! -f "$DECS_CONFIG" ]; then
    exit 0  # No DECS config, silently skip
fi

API_KEY=$(jq -r '.relentlessApiKey // empty' "$DECS_CONFIG")
BASE_URL=$(jq -r '.relentlessUrl // empty' "$DECS_CONFIG")
BUILDSPACE_ID=$(jq -r '.buildspaceId // empty' "$DECS_CONFIG")

if [ -z "$API_KEY" ] || [ -z "$BASE_URL" ] || [ -z "$BUILDSPACE_ID" ]; then
    exit 0  # Missing required config
fi

# === LAYERED DISCOVERY ===
# Walk up from CWD finding ALL .decs.json files (nearest first)
# This enables monorepo support: app-specific decisions + shared decisions

find_all_decs_configs() {
    local dir="$PWD"
    local configs=()
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/.decs.json" ]; then
            configs+=("$dir/.decs.json")
        fi
        dir=$(dirname "$dir")
    done
    echo "${configs[@]}"
}

DECS_CONFIGS=($(find_all_decs_configs))

if [ ${#DECS_CONFIGS[@]} -eq 0 ]; then
    exit 0  # No .decs.json for this repo
fi

# === FETCH & OUTPUT ===

has_output=false

for CONFIG_FILE in "${DECS_CONFIGS[@]}"; do
    SPACE_ID=$(jq -r '.relentlessSpaceId // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ -z "$SPACE_ID" ]; then
        continue
    fi

    # Query decisions in this space
    response=$(curl -s "${BASE_URL}/api/nodes?parentId=${SPACE_ID}&kind=decision&buildspaceId=${BUILDSPACE_ID}" \
      -H "Authorization: Bearer ${API_KEY}")

    # Extract nodes array from response (API returns { "nodes": [...] })
    nodes=$(echo "$response" | jq '.nodes // .' 2>/dev/null)

    # Check if we got any decisions
    decision_count=$(echo "$nodes" | jq 'length' 2>/dev/null)

    if [ -z "$decision_count" ] || [ "$decision_count" -eq 0 ]; then
        continue
    fi

    if [ "$has_output" = false ]; then
        echo "=== DECS: Prior Architectural Decisions ==="
        echo
        has_output=true
    fi

    # Show context header for monorepo (multiple configs)
    if [ ${#DECS_CONFIGS[@]} -gt 1 ]; then
        config_dir=$(dirname "$CONFIG_FILE")
        echo "#### $(basename "$config_dir") decisions"
        echo
    fi

    # Two-tier output: key decisions always shown, recent non-key limited to 10
    KEY_DECISIONS=$(echo "$nodes" | jq '[.[] | select(.content.isKeyDecision == true)]')
    RECENT_DECISIONS=$(echo "$nodes" | jq '[.[] | select(.content.isKeyDecision != true)] | .[0:10]')

    key_count=$(echo "$KEY_DECISIONS" | jq 'length')
    recent_count=$(echo "$RECENT_DECISIONS" | jq 'length')

    if [ "$key_count" -gt 0 ]; then
        echo "### Key Decisions (always active)"
        echo
        echo "$KEY_DECISIONS" | jq -r '.[] | "## \(.title)\n**Updated:** \(.updatedAt | split("T")[0])\n\n**What:** \(.content.what // "—")\n**Why:** \(.content.why // "—")\n**Purpose:** \(.content.purpose // "—")\n**Constraints:** \(.content.constraints // "—")\n\n---\n"'
    fi

    if [ "$recent_count" -gt 0 ]; then
        echo "### Recent Decisions"
        echo
        echo "$RECENT_DECISIONS" | jq -r '.[] | "## \(.title)\n**Updated:** \(.updatedAt | split("T")[0])\n\n**What:** \(.content.what // "—")\n**Why:** \(.content.why // "—")\n**Purpose:** \(.content.purpose // "—")\n**Constraints:** \(.content.constraints // "—")\n\n---\n"'
    fi
done

if [ "$has_output" = true ]; then
    echo
    echo "When making architectural decisions, consider how they relate to the above."
    echo "Key decisions marked above are foundational — contradicting them requires explicit acknowledgment."
fi
