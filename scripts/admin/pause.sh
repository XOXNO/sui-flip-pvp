#!/bin/bash

# Pause coin flip contract operations
# Usage: ./pause.sh <network> <rpc_url> <gas_budget>

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

echo -e "${YELLOW}WARNING: This will pause all coin flip game operations!${NC}"
echo -e "${YELLOW}No new games can be created and no games can be joined while paused.${NC}"
read -p "Are you sure you want to continue? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Operation cancelled${NC}"
    exit 0
fi

echo -e "${GREEN}Pausing coin flip contract...${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"

# Execute the transaction
TX_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "coin_flip" \
    --function "set_pause_state" \
    --args "$ADMIN_CAP" "$GAME_CONFIG" "true" \
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

# Update config to track pause state
UPDATED_CONFIG=$(jq \
    --arg pauseDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.contractState.isPaused = true |
    .lastPauseAction = {
        "action": "pause",
        "transaction": $txDigest,
        "date": $pauseDate
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${RED}Contract is now PAUSED!${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${RED}All game operations have been disabled${NC}"
echo -e "${YELLOW}To resume operations, run 'make unpause NETWORK=$NETWORK'${NC}"
echo -e "${GREEN}========================================${NC}" 