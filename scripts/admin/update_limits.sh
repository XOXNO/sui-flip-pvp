#!/bin/bash

# Update coin flip game bet limits
# Usage: ./update_limits.sh <network> <min_bet> <max_bet> <rpc_url> <gas_budget>

set -e

NETWORK=$1
MIN_BET=$2
MAX_BET=$3
RPC_URL=$4
GAS_BUDGET=$5

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$MIN_BET" ] || [ -z "$MAX_BET" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <min_bet> <max_bet> <rpc_url> <gas_budget>${NC}"
    exit 1
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

# Convert amounts to SUI for display
MIN_BET_SUI=$(echo "scale=9; $MIN_BET/1000000000" | bc)
MAX_BET_SUI=$(echo "scale=9; $MAX_BET/1000000000" | bc)

echo -e "${GREEN}Updating bet limits:${NC}"
echo -e "  Min bet: ${YELLOW}$MIN_BET MIST ($MIN_BET_SUI SUI)${NC}"
echo -e "  Max bet: ${YELLOW}$MAX_BET MIST ($MAX_BET_SUI SUI)${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  AdminCap: ${YELLOW}$ADMIN_CAP${NC}"

# Execute the transaction
TX_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "coin_flip" \
    --function "update_bet_limits" \
    --args "$ADMIN_CAP" "$GAME_CONFIG" "$MIN_BET" "$MAX_BET" \
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

# Update config with new limits
UPDATED_CONFIG=$(jq \
    --arg minBet "$MIN_BET" \
    --arg maxBet "$MAX_BET" \
    --arg updateDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.contractState.minBetAmount = ($minBet | tonumber) |
    .contractState.maxBetAmount = ($maxBet | tonumber) |
    .lastLimitUpdate = {
        "minBetAmount": ($minBet | tonumber),
        "maxBetAmount": ($maxBet | tonumber),
        "minBetSUI": (($minBet | tonumber) / 1000000000),
        "maxBetSUI": (($maxBet | tonumber) / 1000000000),
        "transaction": $txDigest,
        "date": $updateDate
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bet Limits Update Complete!${NC}"
echo -e "  Min bet: ${YELLOW}$MIN_BET MIST ($MIN_BET_SUI SUI)${NC}"
echo -e "  Max bet: ${YELLOW}$MAX_BET MIST ($MAX_BET_SUI SUI)${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${GREEN}All future games will use the new bet limits${NC}"
echo -e "${GREEN}========================================${NC}" 