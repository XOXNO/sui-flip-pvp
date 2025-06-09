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
MIN_BET=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.min_bet_amount')
MAX_BET=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.max_bet_amount')
TREASURY_BALANCE=$(echo "$GAME_CONFIG_INFO" | jq -r '.content.fields.treasury_balance')

# Convert amounts to SUI for display
MIN_BET_SUI=$(echo "scale=9; $MIN_BET/1000000000" | bc)
MAX_BET_SUI=$(echo "scale=9; $MAX_BET/1000000000" | bc)
TREASURY_SUI=$(echo "scale=9; $TREASURY_BALANCE/1000000000" | bc)

# Display contract state with colors
if [ "$IS_PAUSED" = "true" ]; then
    echo -e "  Status: ${RED}PAUSED${NC}"
else
    echo -e "  Status: ${GREEN}ACTIVE${NC}"
fi

echo -e "  Fee Percentage: ${YELLOW}$FEE_PERCENTAGE bps ($(echo "scale=2; $FEE_PERCENTAGE/100" | bc)%)${NC}"
echo -e "  Min Bet: ${YELLOW}$MIN_BET MIST ($MIN_BET_SUI SUI)${NC}"
echo -e "  Max Bet: ${YELLOW}$MAX_BET MIST ($MAX_BET_SUI SUI)${NC}"

if [ "$TREASURY_BALANCE" -gt 0 ]; then
    echo -e "  Treasury: ${YELLOW}$TREASURY_BALANCE MIST ($TREASURY_SUI SUI)${NC}"
else
    echo -e "  Treasury: ${YELLOW}Empty${NC}"
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

# Check for recent withdrawals
LAST_WITHDRAWAL=$(jq -r '.lastWithdrawal // empty' "$CONFIG_FILE")
if [ ! -z "$LAST_WITHDRAWAL" ] && [ "$LAST_WITHDRAWAL" != "null" ]; then
    WITHDRAWAL_AMOUNT=$(echo "$LAST_WITHDRAWAL" | jq -r '.amountSUI')
    WITHDRAWAL_DATE=$(echo "$LAST_WITHDRAWAL" | jq -r '.date')
    WITHDRAWAL_TX=$(echo "$LAST_WITHDRAWAL" | jq -r '.transaction')
    echo -e "  Last Withdrawal: ${YELLOW}$WITHDRAWAL_AMOUNT SUI${NC} on $WITHDRAWAL_DATE (${BLUE}$WITHDRAWAL_TX${NC})"
fi

echo ""

# Display available commands
echo -e "${BLUE}Available Commands:${NC}"
echo -e "  make set-fee FEE_BPS=<bps> NETWORK=$NETWORK"
echo -e "  make update-limits MIN_BET=<amount> MAX_BET=<amount> NETWORK=$NETWORK"
if [ "$IS_PAUSED" = "true" ]; then
    echo -e "  make unpause NETWORK=$NETWORK"
else
    echo -e "  make pause NETWORK=$NETWORK"
fi
if [ "$TREASURY_BALANCE" -gt 0 ]; then
    echo -e "  make withdraw-fees NETWORK=$NETWORK"
fi

echo -e "${GREEN}========================================${NC}" 