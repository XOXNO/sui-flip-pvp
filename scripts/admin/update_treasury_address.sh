#!/bin/bash

# Update treasury address for coin flip contract
# Usage: ./update_treasury_address.sh <network> <new_treasury_address> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]

set -e

NETWORK=$1
NEW_TREASURY_ADDRESS=$2
RPC_URL=$3
GAS_BUDGET=$4
LEDGER_MODE=${5:-false}
LEDGER_ADDRESS=$6
GAS_OBJECT_ID=$7

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
if [ -z "$NETWORK" ] || [ -z "$NEW_TREASURY_ADDRESS" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <new_treasury_address> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]${NC}"
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

echo -e "${GREEN}Updating treasury address...${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  AdminCap: ${YELLOW}$ADMIN_CAP${NC}"
echo -e "  New Treasury Address: ${YELLOW}$NEW_TREASURY_ADDRESS${NC}"

# Get current treasury address for confirmation
CURRENT_CONFIG_INFO=$(sui client object "$GAME_CONFIG" --json 2>/dev/null || echo "{}")
CURRENT_TREASURY=$(echo "$CURRENT_CONFIG_INFO" | jq -r '.content.fields.treasury_address // "unknown"' 2>/dev/null || echo "unknown")

echo -e "  Current Treasury: ${YELLOW}$CURRENT_TREASURY${NC}"

# Confirm the update
read -p "Are you sure you want to update the treasury address? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Operation cancelled${NC}"
    exit 0
fi

# Execute the transaction or generate unsigned tx bytes
if [ "$LEDGER_MODE" = "true" ]; then
    echo -e "${GREEN}🔒 LEDGER MODE: Generating unsigned transaction bytes${NC}"
    
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "update_treasury_address" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" "$NEW_TREASURY_ADDRESS" \
        --serialize-unsigned-transaction \
        --gas "$GAS_OBJECT_ID" \
        --gas-budget "$GAS_BUDGET" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to generate unsigned transaction${NC}"
        echo "Output: $TX_OUTPUT"
        exit 1
    fi
    
    show_ledger_instructions "Update Treasury Address: $NEW_TREASURY_ADDRESS" "$TX_OUTPUT"
    exit 0
else
    # Regular mode - execute transaction directly
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "update_treasury_address" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" "$NEW_TREASURY_ADDRESS" \
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

# Update config with new treasury address info
UPDATED_CONFIG=$(cat "$CONFIG_FILE" | jq --arg treasury "$NEW_TREASURY_ADDRESS" --arg tx "$TX_DIGEST" --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
.lastTreasuryUpdate = {
    "treasuryAddress": $treasury,
    "transaction": $tx,
    "date": $date
}')

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}✅ Treasury address updated successfully!${NC}"
echo -e "  New Treasury Address: ${YELLOW}$NEW_TREASURY_ADDRESS${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "  Config updated: ${YELLOW}$CONFIG_FILE${NC}"

# Verify the update by checking the config
echo -e "${GREEN}Verifying update...${NC}"
UPDATED_CONFIG_INFO=$(sui client object "$GAME_CONFIG" --json 2>/dev/null || echo "{}")
UPDATED_TREASURY=$(echo "$UPDATED_CONFIG_INFO" | jq -r '.content.fields.treasury_address // "unknown"' 2>/dev/null || echo "unknown")

if [ "$UPDATED_TREASURY" = "$NEW_TREASURY_ADDRESS" ]; then
    echo -e "${GREEN}✅ Verification successful - treasury address updated${NC}"
else
    echo -e "${RED}❌ Verification failed - treasury address mismatch${NC}"
    echo -e "  Expected: ${YELLOW}$NEW_TREASURY_ADDRESS${NC}"
    echo -e "  Actual: ${YELLOW}$UPDATED_TREASURY${NC}"
fi

echo -e "${GREEN}Treasury address update complete!${NC}" 