#!/bin/bash

# Migrate configuration settings from old GameConfig to new GameConfig
# Usage: ./migrate_config.sh <network> <rpc_url> <gas_budget>

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
    echo -e "${YELLOW}No upgrades found. Configuration migration not needed.${NC}"
    exit 0
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuration Migration for $NETWORK${NC}"
echo -e "${GREEN}========================================${NC}"

# Get the most recent upgrade info
LAST_UPGRADE_INDEX=$((UPGRADES_COUNT - 1))
OLD_PACKAGE_ID=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].fromPackage" "$CONFIG_FILE")
OLD_ADMIN_CAP=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].oldAdminCap" "$CONFIG_FILE")
OLD_GAME_CONFIG=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].oldGameConfig" "$CONFIG_FILE")
NEW_ADMIN_CAP=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].newAdminCap" "$CONFIG_FILE")
NEW_GAME_CONFIG=$(jq -r ".upgrades[$LAST_UPGRADE_INDEX].newGameConfig" "$CONFIG_FILE")

echo -e "${YELLOW}Migration Details:${NC}"
echo -e "  Old Package: ${YELLOW}$OLD_PACKAGE_ID${NC}"
echo -e "  New Package: ${YELLOW}$CURRENT_PACKAGE_ID${NC}"
echo -e "  Old GameConfig: ${YELLOW}$OLD_GAME_CONFIG${NC}"
echo -e "  New GameConfig: ${YELLOW}$NEW_GAME_CONFIG${NC}"
echo ""

# Get old configuration
echo -e "${GREEN}Reading old configuration...${NC}"
OLD_CONFIG_DATA=$(sui client object "$OLD_GAME_CONFIG" --json)
OLD_FEE_PERCENTAGE=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.fee_percentage')
OLD_MIN_BET=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.min_bet_amount')
OLD_MAX_BET=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.max_bet_amount')
OLD_IS_PAUSED=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.is_paused')

# Get new configuration
echo -e "${GREEN}Reading new configuration...${NC}"
NEW_CONFIG_DATA=$(sui client object "$NEW_GAME_CONFIG" --json)
NEW_FEE_PERCENTAGE=$(echo "$NEW_CONFIG_DATA" | jq -r '.content.fields.fee_percentage')
NEW_MIN_BET=$(echo "$NEW_CONFIG_DATA" | jq -r '.content.fields.min_bet_amount')
NEW_MAX_BET=$(echo "$NEW_CONFIG_DATA" | jq -r '.content.fields.max_bet_amount')
NEW_IS_PAUSED=$(echo "$NEW_CONFIG_DATA" | jq -r '.content.fields.is_paused')

echo -e "${YELLOW}Configuration Comparison:${NC}"
echo -e "  Fee Percentage: ${YELLOW}$OLD_FEE_PERCENTAGE${NC} → ${YELLOW}$NEW_FEE_PERCENTAGE${NC}"
echo -e "  Min Bet Amount: ${YELLOW}$OLD_MIN_BET${NC} → ${YELLOW}$NEW_MIN_BET${NC}"
echo -e "  Max Bet Amount: ${YELLOW}$OLD_MAX_BET${NC} → ${YELLOW}$NEW_MAX_BET${NC}"
echo -e "  Is Paused: ${YELLOW}$OLD_IS_PAUSED${NC} → ${YELLOW}$NEW_IS_PAUSED${NC}"
echo ""

# Check if migration is needed
MIGRATION_NEEDED=false

if [ "$OLD_FEE_PERCENTAGE" != "$NEW_FEE_PERCENTAGE" ]; then
    echo -e "${YELLOW}Fee percentage needs migration${NC}"
    MIGRATION_NEEDED=true
fi

if [ "$OLD_MIN_BET" != "$NEW_MIN_BET" ] || [ "$OLD_MAX_BET" != "$NEW_MAX_BET" ]; then
    echo -e "${YELLOW}Bet limits need migration${NC}"
    MIGRATION_NEEDED=true
fi

if [ "$OLD_IS_PAUSED" != "$NEW_IS_PAUSED" ]; then
    echo -e "${YELLOW}Pause state needs migration${NC}"
    MIGRATION_NEEDED=true
fi

if [ "$MIGRATION_NEEDED" = false ]; then
    echo -e "${GREEN}All configurations already match. No migration needed.${NC}"
    exit 0
fi

# Ask for confirmation
echo -e "${YELLOW}WARNING: This will update the new contract configuration to match the old one!${NC}"
read -p "Are you sure you want to continue? (yes/no) " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${RED}Migration cancelled${NC}"
    exit 0
fi

echo -e "${GREEN}Executing configuration migration...${NC}"

# Migrate fee percentage if different
if [ "$OLD_FEE_PERCENTAGE" != "$NEW_FEE_PERCENTAGE" ]; then
    echo -e "${GREEN}Migrating fee percentage: $OLD_FEE_PERCENTAGE bps...${NC}"
    
    FEE_TX_OUTPUT=$(sui client call \
        --package "$CURRENT_PACKAGE_ID" \
        --module "coin_flip" \
        --function "update_fee_percentage" \
        --args "$NEW_ADMIN_CAP" "$NEW_GAME_CONFIG" "$OLD_FEE_PERCENTAGE" \
        --gas-budget "$GAS_BUDGET" \
        --json 2>&1)
    
    # Extract and validate JSON
    FEE_JSON_START_LINE=$(echo "$FEE_TX_OUTPUT" | grep -n '^{' | head -1 | cut -d: -f1)
    if [ -z "$FEE_JSON_START_LINE" ]; then
        echo -e "${RED}Failed to migrate fee percentage${NC}"
        echo "$FEE_TX_OUTPUT"
        exit 1
    fi
    
    FEE_CLEAN_OUTPUT=$(echo "$FEE_TX_OUTPUT" | tail -n +$FEE_JSON_START_LINE)
    FEE_TX_STATUS=$(echo "$FEE_CLEAN_OUTPUT" | jq -r '.status')
    
    if [ "$FEE_TX_STATUS" != "success" ]; then
        echo -e "${RED}Fee percentage migration failed${NC}"
        echo "$FEE_CLEAN_OUTPUT" | jq '.effects.status'
        exit 1
    fi
    
    FEE_TX_DIGEST=$(echo "$FEE_CLEAN_OUTPUT" | jq -r '.digest')
    echo -e "${GREEN}✅ Fee percentage migrated: $FEE_TX_DIGEST${NC}"
fi

# Migrate bet limits if different
if [ "$OLD_MIN_BET" != "$NEW_MIN_BET" ] || [ "$OLD_MAX_BET" != "$NEW_MAX_BET" ]; then
    echo -e "${GREEN}Migrating bet limits: $OLD_MIN_BET - $OLD_MAX_BET MIST...${NC}"
    
    LIMITS_TX_OUTPUT=$(sui client call \
        --package "$CURRENT_PACKAGE_ID" \
        --module "coin_flip" \
        --function "update_bet_limits" \
        --args "$NEW_ADMIN_CAP" "$NEW_GAME_CONFIG" "$OLD_MIN_BET" "$OLD_MAX_BET" \
        --gas-budget "$GAS_BUDGET" \
        --json 2>&1)
    
    # Extract and validate JSON
    LIMITS_JSON_START_LINE=$(echo "$LIMITS_TX_OUTPUT" | grep -n '^{' | head -1 | cut -d: -f1)
    if [ -z "$LIMITS_JSON_START_LINE" ]; then
        echo -e "${RED}Failed to migrate bet limits${NC}"
        echo "$LIMITS_TX_OUTPUT"
        exit 1
    fi
    
    LIMITS_CLEAN_OUTPUT=$(echo "$LIMITS_TX_OUTPUT" | tail -n +$LIMITS_JSON_START_LINE)
    LIMITS_TX_STATUS=$(echo "$LIMITS_CLEAN_OUTPUT" | jq -r '.status')
    
    if [ "$LIMITS_TX_STATUS" != "success" ]; then
        echo -e "${RED}Bet limits migration failed${NC}"
        echo "$LIMITS_CLEAN_OUTPUT" | jq '.effects.status'
        exit 1
    fi
    
    LIMITS_TX_DIGEST=$(echo "$LIMITS_CLEAN_OUTPUT" | jq -r '.digest')
    echo -e "${GREEN}✅ Bet limits migrated: $LIMITS_TX_DIGEST${NC}"
fi

# Migrate pause state if different
if [ "$OLD_IS_PAUSED" != "$NEW_IS_PAUSED" ]; then
    echo -e "${GREEN}Migrating pause state: $OLD_IS_PAUSED...${NC}"
    
    PAUSE_TX_OUTPUT=$(sui client call \
        --package "$CURRENT_PACKAGE_ID" \
        --module "coin_flip" \
        --function "set_pause_state" \
        --args "$NEW_ADMIN_CAP" "$NEW_GAME_CONFIG" "$OLD_IS_PAUSED" \
        --gas-budget "$GAS_BUDGET" \
        --json 2>&1)
    
    # Extract and validate JSON
    PAUSE_JSON_START_LINE=$(echo "$PAUSE_TX_OUTPUT" | grep -n '^{' | head -1 | cut -d: -f1)
    if [ -z "$PAUSE_JSON_START_LINE" ]; then
        echo -e "${RED}Failed to migrate pause state${NC}"
        echo "$PAUSE_TX_OUTPUT"
        exit 1
    fi
    
    PAUSE_CLEAN_OUTPUT=$(echo "$PAUSE_TX_OUTPUT" | tail -n +$PAUSE_JSON_START_LINE)
    PAUSE_TX_STATUS=$(echo "$PAUSE_CLEAN_OUTPUT" | jq -r '.status')
    
    if [ "$PAUSE_TX_STATUS" != "success" ]; then
        echo -e "${RED}Pause state migration failed${NC}"
        echo "$PAUSE_CLEAN_OUTPUT" | jq '.effects.status'
        exit 1
    fi
    
    PAUSE_TX_DIGEST=$(echo "$PAUSE_CLEAN_OUTPUT" | jq -r '.digest')
    echo -e "${GREEN}✅ Pause state migrated: $PAUSE_TX_DIGEST${NC}"
fi

# Verify final configuration
echo -e "${GREEN}Verifying final configuration...${NC}"
FINAL_CONFIG_DATA=$(sui client object "$NEW_GAME_CONFIG" --json)
FINAL_FEE_PERCENTAGE=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.fee_percentage')
FINAL_MIN_BET=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.min_bet_amount')
FINAL_MAX_BET=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.max_bet_amount')
FINAL_IS_PAUSED=$(echo "$FINAL_CONFIG_DATA" | jq -r '.content.fields.is_paused')

# Update config with migration info
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
UPDATED_CONFIG=$(jq \
    --arg timestamp "$TIMESTAMP" \
    --arg oldFee "$OLD_FEE_PERCENTAGE" \
    --arg newFee "$FINAL_FEE_PERCENTAGE" \
    --arg oldMinBet "$OLD_MIN_BET" \
    --arg newMinBet "$FINAL_MIN_BET" \
    --arg oldMaxBet "$OLD_MAX_BET" \
    --arg newMaxBet "$FINAL_MAX_BET" \
    --arg oldPaused "$OLD_IS_PAUSED" \
    --arg newPaused "$FINAL_IS_PAUSED" \
    '.lastConfigMigration = {
        "date": $timestamp,
        "migratedSettings": {
            "feePercentage": {"from": $oldFee, "to": $newFee},
            "minBetAmount": {"from": $oldMinBet, "to": $newMinBet},
            "maxBetAmount": {"from": $oldMaxBet, "to": $newMaxBet},
            "isPaused": {"from": ($oldPaused | tostring), "to": ($newPaused | tostring)}
        }
    }' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuration Migration Complete!${NC}"
echo -e "  Fee Percentage: ${YELLOW}$FINAL_FEE_PERCENTAGE bps${NC}"
echo -e "  Min Bet: ${YELLOW}$FINAL_MIN_BET MIST${NC}"
echo -e "  Max Bet: ${YELLOW}$FINAL_MAX_BET MIST${NC}"
echo -e "  Is Paused: ${YELLOW}$FINAL_IS_PAUSED${NC}"
echo -e "${GREEN}========================================${NC}" 