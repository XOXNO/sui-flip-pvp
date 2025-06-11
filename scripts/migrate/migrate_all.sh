#!/bin/bash

# Migrate everything (treasury + configuration) from old to new contract
# Usage: ./migrate_all.sh <network> <rpc_url> <gas_budget>

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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Complete Migration for $NETWORK${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${YELLOW}This will migrate:${NC}"
echo -e "  ✓ Treasury funds withdrawn to admin wallet"
echo -e "  ✓ Configuration settings (fee, limits, pause state)"
echo -e "  ✓ All settings preserved and tracked"
echo ""

# Ask for confirmation
echo -e "${YELLOW}WARNING: This will perform a complete migration!${NC}"
read -p "Are you sure you want to continue? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Migration cancelled${NC}"
    exit 0
fi

echo -e "${GREEN}Starting complete migration...${NC}"
echo ""

# Step 1: Withdraw Treasury
echo -e "${GREEN}Step 1/2: Withdrawing Treasury Funds${NC}"
echo -e "${GREEN}====================================${NC}"

if [ -f "$SCRIPT_DIR/migrate_treasury.sh" ]; then
    bash "$SCRIPT_DIR/migrate_treasury.sh" "$NETWORK" "$RPC_URL" "$GAS_BUDGET"
    TREASURY_RESULT=$?
    
    if [ $TREASURY_RESULT -eq 0 ]; then
        echo -e "${GREEN}✅ Treasury withdrawal completed successfully${NC}"
    else
        echo -e "${RED}❌ Treasury withdrawal failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: migrate_treasury.sh not found${NC}"
    exit 1
fi

echo ""

# Step 2: Migrate Configuration
echo -e "${GREEN}Step 2/2: Migrating Configuration Settings${NC}"
echo -e "${GREEN}==========================================${NC}"

if [ -f "$SCRIPT_DIR/migrate_config.sh" ]; then
    bash "$SCRIPT_DIR/migrate_config.sh" "$NETWORK" "$RPC_URL" "$GAS_BUDGET"
    CONFIG_RESULT=$?
    
    if [ $CONFIG_RESULT -eq 0 ]; then
        echo -e "${GREEN}✅ Configuration migration completed successfully${NC}"
    else
        echo -e "${RED}❌ Configuration migration failed${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: migrate_config.sh not found${NC}"
    exit 1
fi

echo ""

# Final verification
echo -e "${GREEN}Final Verification${NC}"
echo -e "${GREEN}==================${NC}"

CONFIG_FILE="deployments/$NETWORK/config.json"
if [ -f "$CONFIG_FILE" ]; then
    CURRENT_PACKAGE_ID=$(jq -r '.packageId' "$CONFIG_FILE")
    CURRENT_GAME_CONFIG=$(jq -r '.gameConfig' "$CONFIG_FILE")
    
    # Get final configuration
    FINAL_CONFIG_DATA=$(sui client object "$CURRENT_GAME_CONFIG" --json)
    FINAL_TREASURY=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.treasury_balance')
    FINAL_FEE=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.fee_percentage')
    FINAL_MIN_BET=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.min_bet_amount')
    FINAL_MAX_BET=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.max_bet_amount')
    FINAL_PAUSED=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.is_paused')
    
    # Convert treasury to SUI
    FINAL_TREASURY_SUI=$(echo "scale=9; $FINAL_TREASURY / 1000000000" | bc -l)
    
    echo -e "${GREEN}Final Contract State:${NC}"
    echo -e "  Package ID: ${YELLOW}$CURRENT_PACKAGE_ID${NC}"
    echo -e "  GameConfig: ${YELLOW}$CURRENT_GAME_CONFIG${NC}"
    echo -e "  Treasury: ${YELLOW}$FINAL_TREASURY_SUI SUI${NC}"
    echo -e "  Fee: ${YELLOW}$FINAL_FEE bps${NC}"
    echo -e "  Min Bet: ${YELLOW}$FINAL_MIN_BET MIST${NC}"
    echo -e "  Max Bet: ${YELLOW}$FINAL_MAX_BET MIST${NC}"
    echo -e "  Paused: ${YELLOW}$FINAL_PAUSED${NC}"
    
    # Update final migration timestamp
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    UPDATED_CONFIG=$(jq \
        --arg timestamp "$TIMESTAMP" \
        '.lastCompleteMigration = {
            "date": $timestamp,
            "treasuryWithdrawn": (has("lastTreasuryWithdrawal")),
            "configMigrated": (has("lastConfigMigration")),
            "finalTreasuryBalance": $finalTreasury,
            "finalTreasuryBalanceSUI": ($finalTreasury | tonumber / 1000000000),
            "note": "Treasury funds withdrawn to admin wallet for manual management"
        }' \
        --arg finalTreasury "$FINAL_TREASURY" \
        "$CONFIG_FILE")
    
    echo "$UPDATED_CONFIG" > "$CONFIG_FILE"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🎉 Complete Migration Successful! 🎉${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All data has been successfully migrated:${NC}"
echo -e "  ✅ Treasury funds withdrawn to admin wallet"
echo -e "  ✅ Configuration settings applied"
echo -e "  ✅ Migration history recorded"
echo -e "  ✅ New contract ready for use"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Update your frontend to use the new package ID"
echo -e "  2. Test the new contract with small amounts"
echo -e "  3. Monitor for any issues"
echo -e "  4. Notify users of the upgrade"
echo ""
echo -e "${GREEN}Migration complete!${NC}" 