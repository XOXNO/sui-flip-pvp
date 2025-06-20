#!/bin/bash

# Check coin flip contract deployment status
# Usage: ./status.sh <network> <rpc_url>

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
    echo -e "${RED}Error: No deployment found for $NETWORK${NC}"
    echo -e "${YELLOW}Run 'make deploy NETWORK=$NETWORK' first${NC}"
    exit 1
fi

# Set the RPC URL
export SUI_RPC_URL=$RPC_URL

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Coin Flip Contract Status - $NETWORK${NC}"
echo -e "${GREEN}========================================${NC}"

# Load deployment config
PACKAGE_ID=$(jq -r '.packageId' "$CONFIG_FILE")
GAME_CONFIG=$(jq -r '.gameConfig' "$CONFIG_FILE")
ADMIN_CAP=$(jq -r '.adminCap' "$CONFIG_FILE")
DEPLOYED_AT=$(jq -r '.deployedAt' "$CONFIG_FILE")
DEPLOYER=$(jq -r '.deployer' "$CONFIG_FILE")

echo -e "${BLUE}Deployment Info:${NC}"
echo -e "  Network: ${YELLOW}$NETWORK${NC}"
echo -e "  Package ID: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  Game Config: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  Admin Cap: ${YELLOW}$ADMIN_CAP${NC}"
echo -e "  Deployed At: ${YELLOW}$DEPLOYED_AT${NC}"
echo -e "  Deployer: ${YELLOW}$DEPLOYER${NC}"
echo ""

# Query current contract state
echo -e "${BLUE}Current Contract State:${NC}"
GAME_CONFIG_INFO=$(sui client object "$GAME_CONFIG" --json 2>/dev/null || echo "{}")

if [ "$GAME_CONFIG_INFO" = "{}" ]; then
    echo -e "${RED}  Error: Could not fetch GameConfig object${NC}"
    exit 1
fi

# Extract contract state
IS_PAUSED=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.is_paused')
FEE_PERCENTAGE=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.fee_percentage')
TREASURY_ADDRESS=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.treasury_address')
MAX_GAMES_PER_TX=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.max_games_per_transaction')

# Display contract state with colors
if [ "$IS_PAUSED" = "true" ]; then
    echo -e "  Status: ${RED}PAUSED${NC}"
else
    echo -e "  Status: ${GREEN}ACTIVE${NC}"
fi

echo -e "  Fee Percentage: ${YELLOW}$FEE_PERCENTAGE bps ($(echo "scale=2; $FEE_PERCENTAGE/100" | bc)%)${NC}"
echo -e "  Treasury Address: ${YELLOW}$TREASURY_ADDRESS${NC}"
echo -e "  Max Games per Tx: ${YELLOW}$MAX_GAMES_PER_TX${NC}"

echo ""
echo -e "${BLUE}Whitelisted Tokens:${NC}"

# Get whitelisted tokens table
WHITELIST_TABLE_ID=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.whitelisted_tokens.fields.id.id')

if [ "$WHITELIST_TABLE_ID" != "null" ] && [ ! -z "$WHITELIST_TABLE_ID" ]; then
    # Query the table to get dynamic fields (tokens)
    DYNAMIC_FIELDS_RESULT=$(sui client dynamic-field "$WHITELIST_TABLE_ID" --json 2>/dev/null || echo '{"data": []}')
    DYNAMIC_FIELDS=$(echo "$DYNAMIC_FIELDS_RESULT" | jq -r '.data')
    
    if [ "$DYNAMIC_FIELDS" != "[]" ] && [ "$DYNAMIC_FIELDS" != "null" ]; then
        # Get the count of tokens
        TOKEN_COUNT=$(echo "$DYNAMIC_FIELDS" | jq length)
        
        # Process each token using jq array indices
        for ((i=0; i<TOKEN_COUNT; i++)); do
            FIELD_NAME=$(echo "$DYNAMIC_FIELDS" | jq -r ".[$i].name.value.name")
            FIELD_OBJECT_ID=$(echo "$DYNAMIC_FIELDS" | jq -r ".[$i].objectId")
            
            # Get the token config details
            TOKEN_CONFIG=$(sui client object "$FIELD_OBJECT_ID" --json 2>/dev/null || echo "{}")
            
            if [ "$TOKEN_CONFIG" != "{}" ]; then
                ENABLED=$(echo "$TOKEN_CONFIG" | jq -r '.content.fields.value.fields.enabled')
                MIN_BET=$(echo "$TOKEN_CONFIG" | jq -r '.content.fields.value.fields.min_bet_amount')
                MAX_BET=$(echo "$TOKEN_CONFIG" | jq -r '.content.fields.value.fields.max_bet_amount')
                
                # Format token name for display
                if [[ "$FIELD_NAME" == *"sui::SUI"* ]]; then
                    TOKEN_DISPLAY="SUI"
                    # Convert MIST to SUI for display (handle bc availability)
                    if command -v bc >/dev/null 2>&1; then
                        MIN_BET_DISPLAY=$(echo "scale=2; $MIN_BET/1000000000" | bc 2>/dev/null | sed 's/\.0*$//' | sed 's/^\./0./')
                        MAX_BET_DISPLAY=$(echo "scale=2; $MAX_BET/1000000000" | bc 2>/dev/null | sed 's/\.0*$//' | sed 's/^\./0./')
                    else
                        echo "No bc found, using awk"
                        MIN_BET_DISPLAY=$(awk "BEGIN {printf \"%.2f\", $MIN_BET/1000000000}")
                        MAX_BET_DISPLAY=$(awk "BEGIN {printf \"%.2f\", $MAX_BET/1000000000}")
                    fi
                    UNIT="SUI"
                else
                    # Extract token symbol from type name
                    TOKEN_DISPLAY=$(echo "$FIELD_NAME" | sed 's/.*::\([^:]*\)$/\1/')
                    MIN_BET_DISPLAY="$MIN_BET"
                    MAX_BET_DISPLAY="$MAX_BET"
                    UNIT="units"
                fi
                
                # Display status with color
                if [ "$ENABLED" = "true" ]; then
                    STATUS="${GREEN}ENABLED${NC}"
                else
                    STATUS="${RED}DISABLED${NC}"
                fi
                
                echo -e "  ${YELLOW}$TOKEN_DISPLAY${NC}: $STATUS - Min: ${YELLOW}$MIN_BET_DISPLAY $UNIT${NC}, Max: ${YELLOW}$MAX_BET_DISPLAY $UNIT${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}No tokens whitelisted${NC}"
    fi
else
    echo -e "  ${RED}Could not query whitelisted tokens${NC}"
fi

echo ""

# Display recent actions from config
echo -e "${BLUE}Recent Actions:${NC}"

# Check for recent fee updates
LAST_FEE_UPDATE=$(jq -r '.lastFeeUpdate // empty' "$CONFIG_FILE")
if [ ! -z "$LAST_FEE_UPDATE" ] && [ "$LAST_FEE_UPDATE" != "null" ]; then
    FEE_DATE=$(echo "$LAST_FEE_UPDATE" | jq -r '.date')
    FEE_BPS=$(echo "$LAST_FEE_UPDATE" | jq -r '.feeBps')
    FEE_TX=$(echo "$LAST_FEE_UPDATE" | jq -r '.transaction')
    echo -e "  Last Fee Update: ${YELLOW}$FEE_BPS bps${NC} on $FEE_DATE (${BLUE}$FEE_TX${NC})"
fi

# Check for recent limit updates
LAST_LIMIT_UPDATE=$(jq -r '.lastLimitUpdate // empty' "$CONFIG_FILE")
if [ ! -z "$LAST_LIMIT_UPDATE" ] && [ "$LAST_LIMIT_UPDATE" != "null" ]; then
    LIMIT_DATE=$(echo "$LAST_LIMIT_UPDATE" | jq -r '.date')
    LIMIT_MIN=$(echo "$LAST_LIMIT_UPDATE" | jq -r '.minBetSUI')
    LIMIT_MAX=$(echo "$LAST_LIMIT_UPDATE" | jq -r '.maxBetSUI')
    LIMIT_TX=$(echo "$LAST_LIMIT_UPDATE" | jq -r '.transaction')
    echo -e "  Last Limit Update: ${YELLOW}$LIMIT_MIN-$LIMIT_MAX SUI${NC} on $LIMIT_DATE (${BLUE}$LIMIT_TX${NC})"
fi

# Check for recent pause actions
LAST_PAUSE_ACTION=$(jq -r '.lastPauseAction // empty' "$CONFIG_FILE")
if [ ! -z "$LAST_PAUSE_ACTION" ] && [ "$LAST_PAUSE_ACTION" != "null" ]; then
    PAUSE_ACTION=$(echo "$LAST_PAUSE_ACTION" | jq -r '.action')
    PAUSE_DATE=$(echo "$LAST_PAUSE_ACTION" | jq -r '.date')
    PAUSE_TX=$(echo "$LAST_PAUSE_ACTION" | jq -r '.transaction')
    echo -e "  Last Pause Action: ${YELLOW}$PAUSE_ACTION${NC} on $PAUSE_DATE (${BLUE}$PAUSE_TX${NC})"
fi

# Check for recent treasury updates
LAST_TREASURY_UPDATE=$(jq -r '.lastTreasuryUpdate // empty' "$CONFIG_FILE")
if [ ! -z "$LAST_TREASURY_UPDATE" ] && [ "$LAST_TREASURY_UPDATE" != "null" ]; then
    TREASURY_UPDATE_ADDRESS=$(echo "$LAST_TREASURY_UPDATE" | jq -r '.treasuryAddress')
    TREASURY_UPDATE_DATE=$(echo "$LAST_TREASURY_UPDATE" | jq -r '.date')
    TREASURY_UPDATE_TX=$(echo "$LAST_TREASURY_UPDATE" | jq -r '.transaction')
    echo -e "  Last Treasury Update: ${YELLOW}$TREASURY_UPDATE_ADDRESS${NC} on $TREASURY_UPDATE_DATE (${BLUE}$TREASURY_UPDATE_TX${NC})"
fi

echo ""

# Display available commands
echo -e "${BLUE}Available Commands:${NC}"
echo -e "  make set-fee FEE_BPS=<bps> NETWORK=$NETWORK"
echo -e "  make add-token TOKEN_TYPE=<type> MIN_BET=<amount> MAX_BET=<amount> NETWORK=$NETWORK"
echo -e "  make update-token-limits TOKEN_TYPE=<type> MIN_BET=<amount> MAX_BET=<amount> NETWORK=$NETWORK"
echo -e "  make remove-token TOKEN_TYPE=<type> NETWORK=$NETWORK"
echo -e "  make list-tokens NETWORK=$NETWORK"
echo -e "  make update-treasury TREASURY_ADDRESS=<address> NETWORK=$NETWORK"
echo -e "  make update-max-games MAX_GAMES=<number> NETWORK=$NETWORK"
if [ "$IS_PAUSED" = "true" ]; then
    echo -e "  make unpause NETWORK=$NETWORK"
else
    echo -e "  make pause NETWORK=$NETWORK"
fi

echo ""
echo -e "${BLUE}Treasury Information:${NC}"
echo -e "  Fees are automatically sent to: ${YELLOW}$TREASURY_ADDRESS${NC}"
echo -e "  No manual withdrawal needed - fees transfer directly during gameplay"

echo -e "${GREEN}========================================${NC}" 