#!/bin/bash

# List whitelisted tokens in coin flip game
# Usage: ./list_tokens.sh <network> <rpc_url>

set -e

NETWORK=$1
RPC_URL=$2

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$RPC_URL" ]; then
    echo -e "${RED}Usage: $0 <network> <rpc_url>${NC}"
    echo -e "${YELLOW}Example: $0 testnet https://fullnode.testnet.sui.io:443${NC}"
    exit 1
fi

# Check if deployment config exists
CONFIG_FILE="deployments/$NETWORK/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Deployment config not found at $CONFIG_FILE${NC}"
    exit 1
fi

# Set the RPC URL
export SUI_RPC_URL=$RPC_URL

# Load deployment config
PACKAGE_ID=$(jq -r '.packageId' "$CONFIG_FILE")
GAME_CONFIG=$(jq -r '.gameConfig' "$CONFIG_FILE")

echo -e "${GREEN}Fetching whitelisted tokens...${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"

# Get the GameConfig object to read whitelisted tokens
OBJECT_OUTPUT=$(sui client object "$GAME_CONFIG" --json 2>&1)

# Extract JSON by finding the line with the opening brace and taking everything from there
JSON_START_LINE=$(echo "$OBJECT_OUTPUT" | grep -n '^{' | head -1 | cut -d: -f1)

if [ -z "$JSON_START_LINE" ]; then
    echo -e "${RED}Failed to find JSON in object output${NC}"
    echo "Raw output:"
    echo "$OBJECT_OUTPUT"
    exit 1
fi

# Extract everything from the JSON start line to the end
CLEAN_OUTPUT=$(echo "$OBJECT_OUTPUT" | tail -n +$JSON_START_LINE)

# Validate that we have valid JSON
if ! echo "$CLEAN_OUTPUT" | jq . > /dev/null 2>&1; then
    echo -e "${RED}Invalid JSON in object output${NC}"
    echo "Extracted content:"
    echo "$CLEAN_OUTPUT"
    exit 1
fi

# Extract whitelisted tokens from the table
# The tokens are stored in the Table structure, we'll extract the visible tokens
TOKENS=$(echo "$CLEAN_OUTPUT" | jq -r '.data.content.fields.whitelisted_tokens.fields.contents // empty')

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Whitelisted Tokens on $NETWORK:${NC}"
echo -e "${GREEN}========================================${NC}"

if [ "$TOKENS" = "null" ] || [ -z "$TOKENS" ] || [ "$TOKENS" = "[]" ]; then
    echo -e "${YELLOW}No tokens currently visible in whitelist${NC}"
    echo -e "${YELLOW}Note: SUI token may be whitelisted but not visible in this view${NC}"
else
    echo "$TOKENS" | jq -r '.[] | "  ✓ " + .fields.name'
fi

# Also show tokens from our local config if available
LOCAL_TOKENS=$(jq -r '.contractState.whitelistedTokens[]? // empty' "$CONFIG_FILE" 2>/dev/null)
if [ -n "$LOCAL_TOKENS" ]; then
    echo -e "${GREEN}Local Config Tracked Tokens:${NC}"
    echo "$LOCAL_TOKENS" | while read -r token; do
        echo -e "  ✓ ${YELLOW}$token${NC}"
    done
fi

echo -e "${GREEN}========================================${NC}" 