#!/bin/bash

# Unpause coin flip contract operations
# Usage: ./unpause.sh <network> <rpc_url> <gas_budget>

set -e

NETWORK=$1
RPC_URL=$2
GAS_BUDGET=$3

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <rpc_url> <gas_budget>${NC}"
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

echo -e "${GREEN}Resuming coin flip contract operations...${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"

# Execute the transaction
TX_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "coin_flip" \
    --function "set_pause_state" \
    --args "$ADMIN_CAP" "$GAME_CONFIG" "false" \
    --gas-budget "$GAS_BUDGET" \
    --json 2>&1)

# Check if transaction was successful
TX_STATUS=$(echo "$TX_OUTPUT" | jq -r '.effects.status.status' 2>/dev/null || echo "failed")

if [ "$TX_STATUS" != "success" ]; then
    echo -e "${RED}Transaction failed!${NC}"
    echo "Output: $TX_OUTPUT"
    exit 1
fi

TX_DIGEST=$(echo "$TX_OUTPUT" | jq -r '.digest')

# Update config to track unpause state
UPDATED_CONFIG=$(jq \
    --arg unpauseDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.contractState.isPaused = false |
    .lastPauseAction = {
        "action": "unpause",
        "transaction": $txDigest,
        "date": $unpauseDate
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Contract is now ACTIVE!${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${GREEN}All game operations have been resumed${NC}"
echo -e "${GREEN}Players can now create and join games${NC}"
echo -e "${GREEN}========================================${NC}" 