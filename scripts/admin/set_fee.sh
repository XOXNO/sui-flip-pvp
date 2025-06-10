#!/bin/bash

# Set coin flip game fee
# Usage: ./set_fee.sh <network> <fee_bps> <rpc_url> <gas_budget>

set -e

NETWORK=$1
FEE_BPS=$2
RPC_URL=$3
GAS_BUDGET=$4

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$FEE_BPS" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <fee_bps> <rpc_url> <gas_budget>${NC}"
    exit 1
fi

# Validate fee_bps (max 100% = 10000 bps)
if [ "$FEE_BPS" -gt 10000 ]; then
    echo -e "${RED}Error: Fee cannot exceed 10000 bps (100%)${NC}"
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

echo -e "${GREEN}Setting game fee to $FEE_BPS bps ($(echo "scale=2; $FEE_BPS/100" | bc)%)${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  AdminCap: ${YELLOW}$ADMIN_CAP${NC}"

# Execute the transaction
TX_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "coin_flip" \
    --function "update_fee_percentage" \
    --args "$ADMIN_CAP" "$GAME_CONFIG" "$FEE_BPS" \
    --gas-budget "$GAS_BUDGET" \
    --json 2>&1)

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

# Update config with new fee
UPDATED_CONFIG=$(jq \
    --arg feeBps "$FEE_BPS" \
    --arg updateDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.contractState.feePercentage = ($feeBps | tonumber) |
    .lastFeeUpdate = {
        "feeBps": ($feeBps | tonumber),
        "feePercentage": (($feeBps | tonumber) / 100),
        "transaction": $txDigest,
        "date": $updateDate
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Fee Update Complete!${NC}"
echo -e "  New Fee: ${YELLOW}$FEE_BPS bps ($(echo "scale=2; $FEE_BPS/100" | bc)%)${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${GREEN}All future games will use the new fee rate${NC}"
echo -e "${GREEN}========================================${NC}" 