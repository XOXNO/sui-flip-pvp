#!/bin/bash

# Update per-token bet limits for coin flip game
# Usage: ./update_token_limits.sh <network> <token_type> <min_bet> <max_bet> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]

set -e

NETWORK=$1
TOKEN_TYPE=$2
MIN_BET=$3
MAX_BET=$4
RPC_URL=$5
GAS_BUDGET=$6
LEDGER_MODE=${7:-false}
LEDGER_ADDRESS=$8
GAS_OBJECT_ID=$9

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
if [ -z "$NETWORK" ] || [ -z "$TOKEN_TYPE" ] || [ -z "$MIN_BET" ] || [ -z "$MAX_BET" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <token_type> <min_bet> <max_bet> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]${NC}"
    echo -e "${YELLOW}Example: $0 testnet 0x2::sui::SUI 100000000 1000000000000 https://fullnode.testnet.sui.io:443 200000000${NC}"
    echo -e "${YELLOW}Example: $0 testnet 0x123::usdc::USDC 1000000 10000000 https://fullnode.testnet.sui.io:443 200000000${NC}"
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

# Validate bet limits
if [ "$MIN_BET" -gt "$MAX_BET" ]; then
    echo -e "${RED}Error: Minimum bet cannot be greater than maximum bet${NC}"
    exit 1
fi

if [ "$MIN_BET" -eq 0 ]; then
    echo -e "${RED}Error: Minimum bet cannot be zero${NC}"
    exit 1
fi

# Validate token type format (should look like package::module::Type)
if [[ ! "$TOKEN_TYPE" =~ ^0x[a-fA-F0-9]+::[a-zA-Z_][a-zA-Z0-9_]*::[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo -e "${RED}Error: Invalid token type format. Expected: 0x<package>::<module>::<Type>${NC}"
    echo -e "${YELLOW}Example: 0x2::sui::SUI or 0x123abc::usdc::USDC${NC}"
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

# Convert amounts to readable format for display
MIN_BET_READABLE=$(echo "scale=9; $MIN_BET/1000000000" | bc 2>/dev/null || echo "$MIN_BET")
MAX_BET_READABLE=$(echo "scale=9; $MAX_BET/1000000000" | bc 2>/dev/null || echo "$MAX_BET")

echo -e "${GREEN}Updating token bet limits: $TOKEN_TYPE${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  AdminCap: ${YELLOW}$ADMIN_CAP${NC}"
echo -e "  New Min Bet: ${YELLOW}$MIN_BET ($MIN_BET_READABLE units)${NC}"
echo -e "  New Max Bet: ${YELLOW}$MAX_BET ($MAX_BET_READABLE units)${NC}"

# Execute the transaction or generate unsigned tx bytes
if [ "$LEDGER_MODE" = "true" ]; then
    echo -e "${GREEN}🔒 LEDGER MODE: Generating unsigned transaction bytes${NC}"
    
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "update_token_limits" \
        --type-args "$TOKEN_TYPE" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" "$MIN_BET" "$MAX_BET" \
        --serialize-unsigned-transaction \
        --gas "$GAS_OBJECT_ID" \
        --gas-budget "$GAS_BUDGET" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to generate unsigned transaction${NC}"
        echo "Output: $TX_OUTPUT"
        exit 1
    fi
    
    show_ledger_instructions "Update Token Limits: $TOKEN_TYPE (Min: $MIN_BET, Max: $MAX_BET)" "$TX_OUTPUT"
    exit 0
else
    # Regular mode - execute transaction directly
    TX_OUTPUT=$(sui client call \
        --package "$PACKAGE_ID" \
        --module "coin_flip" \
        --function "update_token_limits" \
        --type-args "$TOKEN_TYPE" \
        --args "$ADMIN_CAP" "$GAME_CONFIG" "$MIN_BET" "$MAX_BET" \
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

# Update config with the updated token limits
UPDATED_CONFIG=$(jq \
    --arg tokenType "$TOKEN_TYPE" \
    --arg minBet "$MIN_BET" \
    --arg maxBet "$MAX_BET" \
    --arg updateDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.lastTokenLimitUpdate = {
        "action": "update_limits",
        "tokenType": $tokenType,
        "minBet": ($minBet | tonumber),
        "maxBet": ($maxBet | tonumber),
        "transaction": $txDigest,
        "date": $updateDate
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Token Bet Limits Update Complete!${NC}"
echo -e "  Token: ${YELLOW}$TOKEN_TYPE${NC}"
echo -e "  New Min Bet: ${YELLOW}$MIN_BET ($MIN_BET_READABLE units)${NC}"
echo -e "  New Max Bet: ${YELLOW}$MAX_BET ($MAX_BET_READABLE units)${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${GREEN}Games will now use the updated bet limits for this token${NC}"
echo -e "${GREEN}========================================${NC}" 