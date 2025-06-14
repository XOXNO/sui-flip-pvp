#!/bin/bash

# Remove token from coin flip game whitelist
# Usage: ./remove_token.sh <network> <token_type> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]

set -e

NETWORK=$1
TOKEN_TYPE=$2
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
if [ -z "$NETWORK" ] || [ -z "$TOKEN_TYPE" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <token_type> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]${NC}"
    echo -e "${YELLOW}Example: $0 testnet 0x123::usdc::USDC https://fullnode.testnet.sui.io:443 200000000${NC}"
    echo -e "${RED}Warning: Do not remove SUI token as it's the primary currency${NC}"
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

# Validate token type format (should look like package::module::Type)
if [[ ! "$TOKEN_TYPE" =~ ^0x[a-fA-F0-9]+::[a-zA-Z_][a-zA-Z0-9_]*::[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo -e "${RED}Error: Invalid token type format. Expected: 0x<package>::<module>::<Type>${NC}"
    echo -e "${YELLOW}Example: 0x2::sui::SUI or 0x123abc::usdc::USDC${NC}"
    exit 1
fi

# Warning for SUI token removal
if [[ "$TOKEN_TYPE" == "0x2::sui::SUI" ]]; then
    echo -e "${RED}WARNING: You are attempting to remove SUI token from whitelist!${NC}"
    echo -e "${RED}This will prevent all SUI-based games. Are you sure? (y/N)${NC}"
    read -r confirmation
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi
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

echo -e "${GREEN}Removing token from whitelist: $TOKEN_TYPE${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  AdminCap: ${YELLOW}$ADMIN_CAP${NC}"

# Execute the transaction or generate unsigned tx bytes
if [ "$LEDGER_MODE" = "true" ]; then
    echo -e "${GREEN}🔒 LEDGER MODE: Generating unsigned transaction bytes${NC}"
    
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "remove_whitelisted_token" \
        --type-args "$TOKEN_TYPE" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" \
        --serialize-unsigned-transaction \
        --gas "$GAS_OBJECT_ID" \
        --gas-budget "$GAS_BUDGET" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to generate unsigned transaction${NC}"
        echo "Output: $TX_OUTPUT"
        exit 1
    fi
    
    show_ledger_instructions "Remove Token: $TOKEN_TYPE from Whitelist" "$TX_OUTPUT"
    exit 0
else
    # Regular mode - execute transaction directly
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "remove_whitelisted_token" \
        --type-args "$TOKEN_TYPE" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" \
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

# Update config by removing the token from whitelisted tokens
UPDATED_CONFIG=$(jq \
    --arg tokenType "$TOKEN_TYPE" \
    --arg updateDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.contractState.whitelistedTokens = (.contractState.whitelistedTokens // []) - [$tokenType] |
    .lastTokenUpdate = {
        "action": "remove",
        "tokenType": $tokenType,
        "transaction": $txDigest,
        "date": $updateDate
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Token Whitelist Removal Complete!${NC}"
echo -e "  Token: ${YELLOW}$TOKEN_TYPE${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${RED}Games can no longer be created with this token${NC}"
echo -e "${GREEN}========================================${NC}" 