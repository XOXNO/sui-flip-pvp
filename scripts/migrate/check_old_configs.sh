#!/bin/bash

# Check status of old configurations and show migration opportunities
# Usage: ./check_old_configs.sh <network> <rpc_url>

set -e

NETWORK=$1
RPC_URL=$2

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$RPC_URL" ]; then
    echo -e "${RED}Usage: $0 <network> <rpc_url>${NC}"
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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Old Configuration Status - $NETWORK${NC}"
echo -e "${GREEN}========================================${NC}"

# Load current deployment config
CURRENT_PACKAGE_ID=$(jq -r '.packageId' "$CONFIG_FILE")
CURRENT_ADMIN_CAP=$(jq -r '.adminCap' "$CONFIG_FILE")
CURRENT_GAME_CONFIG=$(jq -r '.gameConfig' "$CONFIG_FILE")

echo -e "${BLUE}Current Deployment:${NC}"
echo -e "  Package ID: ${YELLOW}$CURRENT_PACKAGE_ID${NC}"
echo -e "  AdminCap: ${YELLOW}$CURRENT_ADMIN_CAP${NC}"
echo -e "  GameConfig: ${YELLOW}$CURRENT_GAME_CONFIG${NC}"
echo ""

# Check upgrade history
UPGRADES_COUNT=$(jq '.upgrades | length' "$CONFIG_FILE")
if [ "$UPGRADES_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No upgrades found. This is the original deployment.${NC}"
    exit 0
fi

echo -e "${BLUE}Found $UPGRADES_COUNT upgrade(s):${NC}"
echo ""

# Get current configuration
echo -e "${GREEN}Getting current configuration...${NC}"
CURRENT_CONFIG_DATA=$(sui client object "$CURRENT_GAME_CONFIG" --json 2>/dev/null)
if [ $? -eq 0 ]; then
    CURRENT_TREASURY=$(echo "$CURRENT_CONFIG_DATA" | jq -r '.content.fields.treasury_balance')
    CURRENT_FEE=$(echo "$CURRENT_CONFIG_DATA" | jq -r '.content.fields.fee_percentage')
    CURRENT_MIN_BET=$(echo "$CURRENT_CONFIG_DATA" | jq -r '.content.fields.min_bet_amount')
    CURRENT_MAX_BET=$(echo "$CURRENT_CONFIG_DATA" | jq -r '.content.fields.max_bet_amount')
    CURRENT_PAUSED=$(echo "$CURRENT_CONFIG_DATA" | jq -r '.content.fields.is_paused')
    CURRENT_TREASURY_SUI=$(echo "scale=9; $CURRENT_TREASURY / 1000000000" | bc -l)
    
    echo -e "${BLUE}Current Contract Configuration:${NC}"
    echo -e "  Treasury: ${YELLOW}$CURRENT_TREASURY_SUI SUI${NC}"
    echo -e "  Fee: ${YELLOW}$CURRENT_FEE bps${NC}"
    echo -e "  Min Bet: ${YELLOW}$CURRENT_MIN_BET MIST${NC}"
    echo -e "  Max Bet: ${YELLOW}$CURRENT_MAX_BET MIST${NC}"
    echo -e "  Paused: ${YELLOW}$CURRENT_PAUSED${NC}"
else
    echo -e "${RED}Failed to read current configuration${NC}"
    CURRENT_CONFIG_DATA=""
fi

echo ""

# Check each upgrade
MIGRATION_OPPORTUNITIES=false
TOTAL_OLD_TREASURY=0

for ((i=0; i<UPGRADES_COUNT; i++)); do
    OLD_PACKAGE_ID=$(jq -r ".upgrades[$i].fromPackage" "$CONFIG_FILE")
    OLD_ADMIN_CAP=$(jq -r ".upgrades[$i].oldAdminCap" "$CONFIG_FILE")
    OLD_GAME_CONFIG=$(jq -r ".upgrades[$i].oldGameConfig" "$CONFIG_FILE")
    UPGRADE_DATE=$(jq -r ".upgrades[$i].date" "$CONFIG_FILE")
    
    echo -e "${BLUE}Upgrade #$((i+1)) (from $UPGRADE_DATE):${NC}"
    echo -e "  Old Package: ${YELLOW}$OLD_PACKAGE_ID${NC}"
    
    if [ "$OLD_GAME_CONFIG" != "null" ] && [ -n "$OLD_GAME_CONFIG" ]; then
        echo -e "  Old GameConfig: ${YELLOW}$OLD_GAME_CONFIG${NC}"
        
        # Try to get old configuration
        OLD_CONFIG_DATA=$(sui client object "$OLD_GAME_CONFIG" --json 2>/dev/null)
        if [ $? -eq 0 ]; then
            OLD_TREASURY=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.treasury_balance // "0"')
            OLD_FEE=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.fee_percentage')
            OLD_MIN_BET=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.min_bet_amount')
            OLD_MAX_BET=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.max_bet_amount')
            OLD_PAUSED=$(echo "$OLD_CONFIG_DATA" | jq -r '.content.fields.is_paused')
            OLD_TREASURY_SUI=$(echo "scale=9; $OLD_TREASURY / 1000000000" | bc -l)
            
            echo -e "  ${GREEN}✓ Configuration accessible${NC}"
            echo -e "    Treasury: ${YELLOW}$OLD_TREASURY_SUI SUI${NC}"
            echo -e "    Fee: ${YELLOW}$OLD_FEE bps${NC}"
            echo -e "    Min Bet: ${YELLOW}$OLD_MIN_BET MIST${NC}"
            echo -e "    Max Bet: ${YELLOW}$OLD_MAX_BET MIST${NC}"
            echo -e "    Paused: ${YELLOW}$OLD_PAUSED${NC}"
            
            # Check for migration opportunities
            if [ "$OLD_TREASURY" != "0" ] && [ "$OLD_TREASURY" != "null" ]; then
                echo -e "    ${YELLOW}⚠️  Has treasury funds that can be migrated${NC}"
                MIGRATION_OPPORTUNITIES=true
                TOTAL_OLD_TREASURY=$((TOTAL_OLD_TREASURY + OLD_TREASURY))
            fi
            
            if [ -n "$CURRENT_CONFIG_DATA" ]; then
                if [ "$OLD_FEE" != "$CURRENT_FEE" ]; then
                    echo -e "    ${YELLOW}⚠️  Fee percentage differs from current${NC}"
                    MIGRATION_OPPORTUNITIES=true
                fi
                
                if [ "$OLD_MIN_BET" != "$CURRENT_MIN_BET" ] || [ "$OLD_MAX_BET" != "$CURRENT_MAX_BET" ]; then
                    echo -e "    ${YELLOW}⚠️  Bet limits differ from current${NC}"
                    MIGRATION_OPPORTUNITIES=true
                fi
                
                if [ "$OLD_PAUSED" != "$CURRENT_PAUSED" ]; then
                    echo -e "    ${YELLOW}⚠️  Pause state differs from current${NC}"
                    MIGRATION_OPPORTUNITIES=true
                fi
            fi
        else
            echo -e "  ${RED}✗ Configuration not accessible (may have been migrated or deleted)${NC}"
        fi
    else
        echo -e "  ${YELLOW}⚠️  No GameConfig tracked for this upgrade${NC}"
    fi
    
    if [ "$OLD_ADMIN_CAP" != "null" ] && [ -n "$OLD_ADMIN_CAP" ]; then
        echo -e "  Old AdminCap: ${YELLOW}$OLD_ADMIN_CAP${NC}"
        
        # Check if AdminCap still exists
        ADMIN_CAP_DATA=$(sui client object "$OLD_ADMIN_CAP" --json 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo -e "  ${GREEN}✓ AdminCap accessible${NC}"
        else
            echo -e "  ${RED}✗ AdminCap not accessible${NC}"
        fi
    fi
    
    echo ""
done

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Migration Summary${NC}"
echo -e "${GREEN}========================================${NC}"

if [ "$MIGRATION_OPPORTUNITIES" = true ]; then
    echo -e "${YELLOW}Migration opportunities found:${NC}"
    
    if [ "$TOTAL_OLD_TREASURY" -gt 0 ]; then
        TOTAL_OLD_TREASURY_SUI=$(echo "scale=9; $TOTAL_OLD_TREASURY / 1000000000" | bc -l)
        echo -e "  💰 Total treasury funds in old configs: ${YELLOW}$TOTAL_OLD_TREASURY_SUI SUI${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Available Migration Commands:${NC}"
    echo -e "  ${GREEN}make migrate-treasury NETWORK=$NETWORK${NC}    - Migrate treasury funds"
    echo -e "  ${GREEN}make migrate-config NETWORK=$NETWORK${NC}      - Migrate configuration settings"
    echo -e "  ${GREEN}make migrate-all NETWORK=$NETWORK${NC}         - Migrate everything at once"
    echo ""
    echo -e "${YELLOW}Recommendation: Run 'make migrate-all NETWORK=$NETWORK' to migrate everything${NC}"
else
    echo -e "${GREEN}✅ No migration needed. All configurations are up to date.${NC}"
fi

# Check migration history
if jq -e '.lastTreasuryMigration' "$CONFIG_FILE" > /dev/null; then
    LAST_TREASURY_MIGRATION=$(jq -r '.lastTreasuryMigration.date' "$CONFIG_FILE")
    MIGRATED_AMOUNT=$(jq -r '.lastTreasuryMigration.migratedAmountSUI' "$CONFIG_FILE")
    echo ""
    echo -e "${BLUE}Last Treasury Migration:${NC}"
    echo -e "  Date: ${YELLOW}$LAST_TREASURY_MIGRATION${NC}"
    echo -e "  Amount: ${YELLOW}$MIGRATED_AMOUNT SUI${NC}"
fi

if jq -e '.lastConfigMigration' "$CONFIG_FILE" > /dev/null; then
    LAST_CONFIG_MIGRATION=$(jq -r '.lastConfigMigration.date' "$CONFIG_FILE")
    echo ""
    echo -e "${BLUE}Last Configuration Migration:${NC}"
    echo -e "  Date: ${YELLOW}$LAST_CONFIG_MIGRATION${NC}"
fi

if jq -e '.lastCompleteMigration' "$CONFIG_FILE" > /dev/null; then
    LAST_COMPLETE_MIGRATION=$(jq -r '.lastCompleteMigration.date' "$CONFIG_FILE")
    echo ""
    echo -e "${BLUE}Last Complete Migration:${NC}"
    echo -e "  Date: ${YELLOW}$LAST_COMPLETE_MIGRATION${NC}"
fi

echo ""
echo -e "${GREEN}Check complete!${NC}" 