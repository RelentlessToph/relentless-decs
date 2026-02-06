#!/bin/bash
# DECS Installation Script for Relentless
# Installs hooks and skill for decision tracking via Relentless API

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
DECS_CONFIG="$CLAUDE_DIR/decs-config.json"

# Create directories
mkdir -p "$CLAUDE_DIR/hooks"
mkdir -p "$CLAUDE_DIR/skills/init-decs-project"

# Copy hooks
cp "$SCRIPT_DIR/hooks/"*.sh "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR/hooks/"*.sh
echo "Hooks installed"

# Copy skill
cp "$SCRIPT_DIR/skills/init-decs-project/SKILL.md" "$CLAUDE_DIR/skills/init-decs-project/"
echo "Skill installed"

# Merge hook entries into settings.json
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOKS_FILE="$SCRIPT_DIR/decs-hooks.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{"hooks":{}}' | jq --slurpfile h "$HOOKS_FILE" '.hooks = $h[0]' > "$SETTINGS_FILE"
    echo "Created settings.json with DECS hooks"
else
    # Merge DECS hooks into existing settings (idempotent: remove old DECS entries first)
    jq --slurpfile h "$HOOKS_FILE" '
      def remove_decs: [.[]? | .hooks = [.hooks[]? | select(.command | test("(get-decisions|decs-context|decs-stop)\\.sh") | not)] | select(.hooks | length > 0)];
      .hooks.SessionStart = ((.hooks.SessionStart // []) | remove_decs) + $h[0].SessionStart |
      .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | remove_decs) + $h[0].UserPromptSubmit |
      .hooks.Stop = ((.hooks.Stop // []) | remove_decs) + $h[0].Stop
    ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    echo "Merged DECS hooks into settings.json"
fi

echo ""
echo "DECS installed successfully!"
echo ""

# Check if config exists
if [ -f "$DECS_CONFIG" ]; then
    echo "Config found at $DECS_CONFIG"
else
    echo "To complete setup, create ~/.claude/decs-config.json:"
    echo ""
    echo "  1. Generate an API key from your Relentless account settings"
    echo "  2. Find your Buildspace ID in the URL bar (e.g. /workspace/019c2f...)"
    echo "  3. Create the config file:"
    echo ""
    echo '     {'
    echo '       "relentlessApiKey": "rlnt_YOUR_KEY",'
    echo '       "relentlessUrl": "https://relentless.build",'
    echo '       "buildspaceId": "your-buildspace-id"'
    echo '     }'
    echo ""
fi

echo "To enable DECS in a repo:"
echo ""
echo "  /init-decs-project [project-name]"
echo ""
echo "  Or link to an existing Decisions space:"
echo "  /init-decs-project <space-id>"
