#!/bin/bash

# Withdraw accumulated fees from coin flip contract
# Usage: ./withdraw_fees.sh <network> <rpc_url> <gas_budget>

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

echo -e "${GREEN}Checking treasury balance...${NC}"

# First, let's check the current treasury balance by querying the GameConfig object
TREASURY_INFO=$(sui client object "$GAME_CONFIG" --json 2>/dev/null || echo "{}")
TREASURY_BALANCE=$(echo "$TREASURY_INFO" | jq -r '.content.fields.treasury_balance // 0' 2>/dev/null || echo "0")

if [ "$TREASURY_BALANCE" = "0" ] || [ -z "$TREASURY_BALANCE" ]; then
    echo -e "${RED}Treasury is empty, nothing to withdraw${NC}"
    exit 0
fi

# Convert to SUI for display
TREASURY_SUI=$(echo "scale=9; $TREASURY_BALANCE/1000000000" | bc)

echo -e "${GREEN}Withdrawing fees from treasury...${NC}"
echo -e "  Amount: ${YELLOW}$TREASURY_BALANCE MIST ($TREASURY_SUI SUI)${NC}"
echo -e "  Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  GameConfig: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  AdminCap: ${YELLOW}$ADMIN_CAP${NC}"

# Confirm withdrawal
read -p "Are you sure you want to withdraw all fees? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Operation cancelled${NC}"
    exit 0
fi

# Execute the transaction
TX_OUTPUT=$(sui client call \
    --package "$PACKAGE_ID" \
    --module "coin_flip" \
    --function "withdraw_fees" \
    --args "$ADMIN_CAP" "$GAME_CONFIG" \
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

# Update config with withdrawal info
UPDATED_CONFIG=$(jq \
    --arg withdrawnAmount "$TREASURY_BALANCE" \
    --arg withdrawDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.contractState.treasuryBalance = 0 |
    .lastWithdrawal = {
        "amount": ($withdrawnAmount | tonumber),
        "amountSUI": (($withdrawnAmount | tonumber) / 1000000000),
        "transaction": $txDigest,
        "date": $withdrawDate
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Fee Withdrawal Complete!${NC}"
echo -e "  Amount withdrawn: ${YELLOW}$TREASURY_BALANCE MIST ($TREASURY_SUI SUI)${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "  Recipient: ${YELLOW}$(sui client active-address)${NC}"
echo -e "${GREEN}Treasury is now empty${NC}"
echo -e "${GREEN}========================================${NC}" 