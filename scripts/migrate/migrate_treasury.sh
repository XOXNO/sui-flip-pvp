#!/bin/bash

# Withdraw treasury from old GameConfig to admin wallet for manual management
# Usage: ./migrate_treasury.sh <network> <rpc_url> <gas_budget>

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

# Load current deployment config
CURRENT_PACKAGE_ID=$(jq -r '.packageId' "$CONFIG_FILE")
CURRENT_ADMIN_CAP=$(jq -r '.adminCap' "$CONFIG_FILE")
CURRENT_GAME_CONFIG=$(jq -r '.gameConfig' "$CONFIG_FILE")

# Check if there are any upgrades
UPGRADES_COUNT=$(jq '.upgrades | length' "$CONFIG_FILE")
if [ "$UPGRADES_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No upgrades found. Treasury withdrawal not needed.${NC}"
    exit 0
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Treasury Withdrawal for $NETWORK${NC}"
echo -e "${GREEN}========================================${NC}"

# Get the most recent upgrade info
LAST_UPGRADE_INDEX=$((UPGRADES_COUNT - 1))
OLD_PACKAGE_ID=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].fromPackage" "$CONFIG_FILE")
OLD_ADMIN_CAP=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].oldAdminCap" "$CONFIG_FILE")
OLD_GAME_CONFIG=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].oldGameConfig" "$CONFIG_FILE")
NEW_ADMIN_CAP=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].newAdminCap" "$CONFIG_FILE")
NEW_GAME_CONFIG=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].newGameConfig" "$CONFIG_FILE")

echo -e "${YELLOW}Withdrawal Details:${NC}"
echo -e "  Old Package: ${YELLOW}$OLD_PACKAGE_ID${NC}"
echo -e "  Current Package: ${YELLOW}$CURRENT_PACKAGE_ID${NC}"
echo -e "  Old AdminCap: ${YELLOW}$OLD_ADMIN_CAP${NC}"
echo -e "  Old GameConfig: ${YELLOW}$OLD_GAME_CONFIG${NC}"
echo -e "  Destination: ${YELLOW}Admin Wallet${NC}"
echo ""

# Check treasury balance in old config
echo -e "${GREEN}Checking old treasury balance...${NC}"
OLD_TREASURY_BALANCE=$(sui client object "$OLD_GAME_CONFIG" --json | jq -r '.content.fields.treasury_balance // "0"')

if [ "$OLD_TREASURY_BALANCE" = "0" ] || [ "$OLD_TREASURY_BALANCE" = "null" ]; then
    echo -e "${YELLOW}Old treasury is empty. No migration needed.${NC}"
    exit 0
fi

echo -e "${GREEN}Old treasury balance: ${YELLOW}$OLD_TREASURY_BALANCE MIST${NC}"

# Convert MIST to SUI for display
OLD_TREASURY_SUI=$(echo "scale=9; $OLD_TREASURY_BALANCE / 1000000000" | bc -l)
echo -e "${GREEN}Old treasury balance: ${YELLOW}$OLD_TREASURY_SUI SUI${NC}"

# Ask for confirmation
echo -e "${YELLOW}WARNING: This will withdraw all treasury funds from old contract to your admin wallet!${NC}"
read -p "Are you sure you want to continue? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Treasury withdrawal cancelled${NC}"
    exit 0
fi

echo -e "${GREEN}Withdrawing treasury from old package to admin wallet...${NC}"

# Execute the withdrawal transaction from old package
TX_OUTPUT=$(sui client call \
    --package "$OLD_PACKAGE_ID" \
    --module "coin_flip" \
    --function "withdraw_fees" \
    --args "$OLD_ADMIN_CAP" "$OLD_GAME_CONFIG" \
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

# Check if it's valid JSON
if ! echo "$CLEAN_OUTPUT" | jq . > /dev/null 2>&1; then
    echo -e "${RED}Transaction output is not valid JSON${NC}"
    echo "Clean output:"
    echo "$CLEAN_OUTPUT"
    exit 1
fi

# Check transaction status
TX_STATUS=$(echo "$CLEAN_OUTPUT" | jq -r '.status')
if [ "$TX_STATUS" != "success" ]; then
    echo -e "${RED}Transaction failed with status: $TX_STATUS${NC}"
    echo "Error details:"
    echo "$CLEAN_OUTPUT" | jq '.effects.status'
    exit 1
fi

# Get transaction digest
TX_DIGEST=$(echo "$CLEAN_OUTPUT" | jq -r '.digest')

echo -e "${GREEN}✅ Treasury withdrawal successful!${NC}"
echo -e "${GREEN}Transaction: ${YELLOW}$TX_DIGEST${NC}"

# Verify withdrawal by checking old treasury is now empty
echo -e "${GREEN}Verifying withdrawal...${NC}"
FINAL_OLD_TREASURY=$(sui client object "$OLD_GAME_CONFIG" --json | jq -r '.content.fields.treasury_balance')
echo -e "${GREEN}Old treasury balance (should be 0): ${YELLOW}$FINAL_OLD_TREASURY MIST${NC}"

# Note: Funds are now in admin wallet, not in new treasury
echo -e "${YELLOW}Note: Treasury funds have been withdrawn to admin wallet.${NC}"
echo -e "${YELLOW}You can now manually manage these funds as needed.${NC}"

# Update config with withdrawal info
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED_CONFIG=$(jq \
    --arg txDigest "$TX_DIGEST" \
    --arg timestamp "$TIMESTAMP" \
    --arg withdrawnAmount "$OLD_TREASURY_BALANCE" \
    --arg finalOldBalance "$FINAL_OLD_TREASURY" \
    '.lastTreasuryWithdrawal = {
        "transaction": $txDigest,
        "date": $timestamp,
        "withdrawnAmount": $withdrawnAmount,
        "finalOldTreasuryBalance": $finalOldBalance,
        "withdrawnAmountSUI": ($withdrawnAmount | tonumber / 1000000000),
        "note": "Funds withdrawn to admin wallet for manual management"
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Treasury Withdrawal Complete!${NC}"
echo -e "  Withdrawn Amount: ${YELLOW}$OLD_TREASURY_SUI SUI${NC}"
echo -e "  Destination: ${YELLOW}Admin Wallet${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "  Status: ${YELLOW}Funds now available for manual management${NC}"
echo -e "${GREEN}========================================${NC}" 