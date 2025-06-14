#!/bin/bash

# Unpause coin flip contract operations
# Usage: ./unpause.sh <network> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]

set -e

NETWORK=$1
RPC_URL=$2
GAS_BUDGET=$3
LEDGER_MODE=${4:-false}
LEDGER_ADDRESS=$5
GAS_OBJECT_ID=$6

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source Ledger utilities
SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
source "$SCRIPT_DIR/../utils/ledger_utils.sh"

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]${NC}"
    exit 1
fi

# Setup Ledger gas selection if needed
if ! setup_ledger_gas "$LEDGER_MODE" "$LEDGER_ADDRESS" "$GAS_OBJECT_ID" "$GAS_BUDGET"; then
    exit 1
fi

# Use the selected gas object ID
if [ "$LEDGER_MODE" = "true" ]; then
    GAS_OBJECT_ID="$SELECTED_GAS_OBJECT_ID"
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

# Execute the transaction or generate unsigned tx bytes
if [ "$LEDGER_MODE" = "true" ]; then
    echo -e "${GREEN}🔒 LEDGER MODE: Generating unsigned transaction bytes${NC}"
    
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "set_pause_state" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" "false" \
        --serialize-unsigned-transaction \
        --gas "$GAS_OBJECT_ID" \
        --gas-budget "$GAS_BUDGET" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to generate unsigned transaction${NC}"
        echo "Output: $TX_OUTPUT"
        exit 1
    fi
    
    show_ledger_instructions "UNPAUSE Contract" "$TX_OUTPUT"
    exit 0
else
    # Regular mode - execute transaction directly
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "set_pause_state" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" "false" \
        --gas-budget "$GAS_BUDGET" \
        --json 2>&1)
fi

# Extract JSON by finding the line with the opening brace and taking everything from there
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