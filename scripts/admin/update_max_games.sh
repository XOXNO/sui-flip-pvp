#!/bin/bash

# Update coin flip max games per transaction limit
# Usage: ./update_max_games.sh <network> <max_games> <rpc_url> <gas_budget>

set -e

NETWORK=$1
MAX_GAMES=$2
RPC_URL=$3
GAS_BUDGET=$4

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$MAX_GAMES" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <max_games> <rpc_url> <gas_budget>${NC}"
    exit 1
fi

# Validate max games (must be positive and reasonable)
if [ "$MAX_GAMES" -le 0 ]; then
    echo -e "${RED}Error: Max games must be greater than 0${NC}"
    exit 1
fi

if [ "$MAX_GAMES" -gt 1000 ]; then
    echo -e "${RED}Error: Max games cannot exceed 1000${NC}"
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
ADMIN_CAP=$(jq -r '.adminCap' "$CONFIG_FILE")

echo -e "${GREEN}Updating max games per transaction to $MAX_GAMES${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  AdminCap: ${YELLOW}$ADMIN_CAP${NC}"

# Execute the transaction and capture both stdout and stderr
TX_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "coin_flip" \
    --function "update_max_games_per_transaction" \
    --args "$ADMIN_CAP" "$GAME_CONFIG" "$MAX_GAMES" \
    --gas-budget "$GAS_BUDGET" \
    --json 2>&1)

# Extract JSON by finding the line with the opening brace and taking everything from there
# This approach is more reliable across different shells and operating systems
JSON_START_LINE=$(echo "$TX_OUTPUT" | grep -n '^{' | head -1 | cut -d: -f1)

if [ -z "$JSON_START_LINE" ]; then
    echo -e "${RED}Failed to find JSON in transaction output${NC}"
    echo "Raw output:"
    echo "$TX_OUTPUT"
    exit 1
fi

# Extract everything from the JSON start line to the end
CLEAN_OUTPUT=$(echo "$TX_OUTPUT" | tail -n +$JSON_START_LINE)

# Validate that we have valid JSON
if ! echo "$CLEAN_OUTPUT" | jq . > /dev/null 2>&1; then
    echo -e "${RED}Invalid JSON in transaction output${NC}"
    echo "Extracted content:"
    echo "$CLEAN_OUTPUT"
    exit 1
fi

# Check if transaction was successful
TX_STATUS=$(echo "$CLEAN_OUTPUT" | jq -r '.effects.status.status' 2>/dev/null || echo "failed")

if [ "$TX_STATUS" != "success" ]; then
    echo -e "${RED}Transaction failed!${NC}"
    echo "Output: $TX_OUTPUT"
    exit 1
fi

TX_DIGEST=$(echo "$CLEAN_OUTPUT" | jq -r '.digest')

# Update config with new max games limit
UPDATED_CONFIG=$(jq \
    --arg maxGames "$MAX_GAMES" \
    --arg txDigest "$TX_DIGEST" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '.contractState.maxGamesPerTransaction = ($maxGames | tonumber) |
     .lastMaxGamesUpdate = {
         "date": $timestamp,
         "maxGames": ($maxGames | tonumber),
         "transaction": $txDigest
     }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}✅ Max games per transaction updated successfully!${NC}"
echo -e "  New Limit: ${YELLOW}$MAX_GAMES games per transaction${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "  Updated config saved to: ${YELLOW}$CONFIG_FILE${NC}" 