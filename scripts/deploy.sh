#!/bin/bash

# Deploy Coin Flip Game
# Usage: ./deploy.sh <network> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]

set -e

NETWORK=$1
RPC_URL=$2
GAS_BUDGET=$3
LEDGER_MODE=${4:-false}
LEDGER_ADDRESS=$5
GAS_OBJECT_ID=$6

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to auto-select gas coin from Ledger address
auto_select_gas_coin() {
    local ledger_addr=$1
    echo -e "${GREEN}Auto-selecting gas coin for Ledger address: $ledger_addr${NC}" >&2
    
    # Get gas coins for the address
    local gas_output=$(sui client gas "$ledger_addr" --json 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$gas_output" ]; then
        echo -e "${RED}Failed to query gas coins for address: $ledger_addr${NC}" >&2
        return 1
    fi
    
    # Extract the first gas coin with sufficient balance
    local selected_gas=$(echo "$gas_output" | jq -r --arg budget "$GAS_BUDGET" '.[] | select(.mistBalance >= ($budget | tonumber)) | .gasCoinId' | head -1)
    
    if [ -z "$selected_gas" ] || [ "$selected_gas" = "null" ]; then
        echo -e "${RED}No gas coin found with sufficient balance (need $GAS_BUDGET MIST)${NC}" >&2
        echo -e "${YELLOW}Available gas coins:${NC}" >&2
        echo "$gas_output" | jq -r '.[] | "  \(.gasCoinId): \(.mistBalance) MIST"' 2>/dev/null || echo "  None found" >&2
        return 1
    fi
    
    echo -e "${GREEN}Selected gas coin: $selected_gas${NC}" >&2
    echo "$selected_gas"
}

# Check parameters
if [ -z "$NETWORK" ] || [ -z "$RPC_URL" ] || [ -z "$GAS_BUDGET" ]; then
    echo -e "${RED}Usage: $0 <network> <rpc_url> <gas_budget> [ledger_mode] [ledger_address] [gas_object_id]${NC}"
    exit 1
fi

# Check ledger mode requirements and auto-select gas if needed
if [ "$LEDGER_MODE" = "true" ]; then
    if [ -n "$LEDGER_ADDRESS" ] && [ -z "$GAS_OBJECT_ID" ]; then
        # Auto-select gas coin from Ledger address
        GAS_OBJECT_ID=$(auto_select_gas_coin "$LEDGER_ADDRESS")
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to auto-select gas coin${NC}"
            exit 1
        fi
    elif [ -z "$LEDGER_ADDRESS" ] && [ -z "$GAS_OBJECT_ID" ]; then
        echo -e "${RED}Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true${NC}"
        echo -e "${YELLOW}Usage 1 (auto gas): $0 $NETWORK $RPC_URL $GAS_BUDGET true <ledger_address>${NC}"
        echo -e "${YELLOW}Usage 2 (manual gas): $0 $NETWORK $RPC_URL $GAS_BUDGET true \"\" <gas_object_id>${NC}"
        exit 1
    fi
    
    if [ -z "$GAS_OBJECT_ID" ]; then
        echo -e "${RED}Error: Could not determine gas object ID${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Using gas object: $GAS_OBJECT_ID${NC}"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deploying Coin Flip Game to $NETWORK${NC}"
echo -e "${GREEN}========================================${NC}"

# Set the RPC URL for sui client
export SUI_RPC_URL=$RPC_URL

# Check if deployment config exists
CONFIG_FILE="deployments/$NETWORK/config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Warning: Deployment config already exists for $NETWORK${NC}"
    echo -e "${YELLOW}Use 'make upgrade' instead if you want to upgrade${NC}"
    read -p "Continue with fresh deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Create deployment directory
mkdir -p deployments/$NETWORK

echo -e "${GREEN}Publishing package...${NC}"

# First, let's check SUI client status
echo -e "${GREEN}Checking SUI client status...${NC}"
sui client active-env
echo ""

# Handle Ledger mode vs regular mode
if [ "$LEDGER_MODE" = "true" ]; then
    echo -e "${GREEN}🔒 LEDGER MODE: Generating unsigned transaction bytes${NC}"
    echo -e "${GREEN}Running: sui client publish --serialize-unsigned-transaction --gas $GAS_OBJECT_ID --gas-budget $GAS_BUDGET${NC}"
    
    PUBLISH_OUTPUT=$(sui client publish --serialize-unsigned-transaction --gas "$GAS_OBJECT_ID" --gas-budget $GAS_BUDGET 2>&1)
    PUBLISH_EXIT_CODE=$?
    
    if [ $PUBLISH_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}Failed to generate unsigned transaction${NC}"
        echo "Output: $PUBLISH_OUTPUT"
        exit 1
    fi
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🔒 LEDGER TRANSACTION READY${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}Transaction Bytes:${NC}"
    echo "$PUBLISH_OUTPUT"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo -e "1. Copy the transaction bytes above"
    echo -e "2. Go to: ${BLUE}https://multisig-toolkit.mystenlabs.com/offline-signer${NC}"
    echo -e "3. Paste transaction bytes and connect your Ledger"
    echo -e "4. Sign the transaction to get the signature"
    echo -e "5. Go to: ${BLUE}https://multisig-toolkit.mystenlabs.com/execute-transaction${NC}"
    echo -e "6. Paste transaction bytes + signature and execute"
    echo -e "7. After execution, you'll get the transaction digest"
    echo -e "8. Update your deployment config manually with the new package details"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    # Regular mode - execute transaction directly
    echo -e "${GREEN}Running: sui client publish --gas-budget $GAS_BUDGET --json${NC}"
    PUBLISH_OUTPUT=$(sui client publish --gas-budget $GAS_BUDGET --json 2>&1)
    PUBLISH_EXIT_CODE=$?
    
    # Check if publish was successful
    if [ $PUBLISH_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}Failed to publish package${NC}"
        echo "Output: $PUBLISH_OUTPUT"
        exit 1
    fi
fi

# Try to extract JSON from the output (in case there are warnings before JSON)
JSON_OUTPUT=""
while IFS= read -r line; do
    if [[ "$line" == "{"* ]]; then
        JSON_OUTPUT="$line"
        # Continue reading to get the complete JSON object
        while IFS= read -r line; do
            JSON_OUTPUT="$JSON_OUTPUT$line"
        done
        break
    fi
done <<< "$PUBLISH_OUTPUT"

# If no JSON found, try the original output
if [ -z "$JSON_OUTPUT" ]; then
    JSON_OUTPUT="$PUBLISH_OUTPUT"
fi

# Check if output is valid JSON
if ! echo "$JSON_OUTPUT" | jq . > /dev/null 2>&1; then
    echo -e "${RED}Publish output is not valid JSON${NC}"
    echo "Raw output:"
    echo "$PUBLISH_OUTPUT"
    echo ""
    echo "Extracted JSON attempt:"
    echo "$JSON_OUTPUT"
    exit 1
fi

# Use the cleaned JSON output
PUBLISH_OUTPUT="$JSON_OUTPUT"

# Extract package ID from the output
PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.type == "published") | .packageId')

if [ -z "$PACKAGE_ID" ] || [ "$PACKAGE_ID" = "null" ]; then
    echo -e "${RED}Failed to extract package ID from publish output${NC}"
    echo "Output: $PUBLISH_OUTPUT"
    exit 1
fi

echo -e "${GREEN}Package published: $PACKAGE_ID${NC}"

# Extract created objects
echo -e "${GREEN}Extracting created objects...${NC}"

# Get AdminCap (transferred to sender)
ADMIN_CAP=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType and (.objectType | contains("AdminCap"))) | .objectId')

# Get GameConfig (shared object)
GAME_CONFIG=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType and (.objectType | contains("GameConfig"))) | .objectId')

# Get the transaction digest
TX_DIGEST=$(echo "$PUBLISH_OUTPUT" | jq -r '.digest')

# Validate extracted objects
if [ -z "$ADMIN_CAP" ] || [ "$ADMIN_CAP" = "null" ]; then
    echo -e "${RED}Failed to extract AdminCap${NC}"
    exit 1
fi

if [ -z "$GAME_CONFIG" ] || [ "$GAME_CONFIG" = "null" ]; then
    echo -e "${RED}Failed to extract GameConfig${NC}"
    exit 1
fi

# Create deployment configuration
DEPLOYMENT_INFO=$(cat <<EOF
{
  "network": "$NETWORK",
  "packageId": "$PACKAGE_ID",
  "adminCap": "$ADMIN_CAP",
  "gameConfig": "$GAME_CONFIG",
  "deploymentTx": "$TX_DIGEST",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "deployer": "$(sui client active-address)",
  "contractState": {
    "isPaused": false,
    "feePercentage": 250,
    "minBetAmount": 10000000,
    "maxBetAmount": 1000000000000,
    "treasuryBalance": 0
  }
}
EOF
)

# Save deployment info
echo "$DEPLOYMENT_INFO" > "$CONFIG_FILE"

echo -e "${GREEN}Deployment info saved to $CONFIG_FILE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Summary:${NC}"
echo -e "  Package ID: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  Admin Cap: ${YELLOW}$ADMIN_CAP${NC}"
echo -e "  Game Config: ${YELLOW}$GAME_CONFIG${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${GREEN}Contract is ready for use!${NC}"
echo -e "${GREEN}Available admin commands:${NC}"
echo -e "  - make set-fee FEE_BPS=<bps> NETWORK=$NETWORK"
echo -e "  - make update-limits MIN_BET=<amount> MAX_BET=<amount> NETWORK=$NETWORK"
echo -e "  - make pause NETWORK=$NETWORK"
echo -e "  - make unpause NETWORK=$NETWORK"
echo -e "  - make withdraw-fees NETWORK=$NETWORK"

echo -e "${GREEN}Deployment complete!${NC}" 