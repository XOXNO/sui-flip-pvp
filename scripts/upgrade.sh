#!/bin/bash

# Upgrade Coin Flip Game contract
# Usage: ./upgrade.sh <network> <rpc_url> <gas_budget>

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
    echo -e "${RED}Error: No deployment found for $NETWORK${NC}"
    echo -e "${YELLOW}Run 'make deploy NETWORK=$NETWORK' first${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Upgrading Coin Flip Game on $NETWORK${NC}"
echo -e "${GREEN}========================================${NC}"

# Set the RPC URL for sui client
export SUI_RPC_URL=$RPC_URL

# Load deployment config
PACKAGE_ID=$(jq -r '.packageId' "$CONFIG_FILE")
OLD_ADMIN_CAP=$(jq -r '.adminCap' "$CONFIG_FILE")
OLD_GAME_CONFIG=$(jq -r '.gameConfig' "$CONFIG_FILE")
echo -e "${YELLOW}Current Package ID: $PACKAGE_ID${NC}"

echo -e "${YELLOW}Note: SUI packages are immutable. To 'upgrade', you need to:${NC}"
echo -e "${YELLOW}1. Deploy a new package with your changes${NC}"
echo -e "${YELLOW}2. Migrate data if needed${NC}"
echo -e "${YELLOW}3. Update your frontend to use the new package${NC}"
echo ""

read -p "Do you want to deploy a new package version? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Upgrade cancelled${NC}"
    exit 0
fi

echo -e "${GREEN}Publishing new package version...${NC}"

# Publish the package and capture output
PUBLISH_OUTPUT=$(sui client publish --gas-budget $GAS_BUDGET --json 2>&1)
PUBLISH_EXIT_CODE=$?

# Check if publish was successful
if [ $PUBLISH_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}Failed to publish new package${NC}"
    echo "Output: $PUBLISH_OUTPUT"
    exit 1
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
    exit 1
fi

# Use the cleaned JSON output
PUBLISH_OUTPUT="$JSON_OUTPUT"

# Extract new package ID from the output
NEW_PACKAGE_ID=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.type == "published") | .packageId')

if [ -z "$NEW_PACKAGE_ID" ] || [ "$NEW_PACKAGE_ID" = "null" ]; then
    echo -e "${RED}Failed to extract new package ID from publish output${NC}"
    echo "Output: $PUBLISH_OUTPUT"
    exit 1
fi

echo -e "${GREEN}New package published: $NEW_PACKAGE_ID${NC}"

# Extract new AdminCap and GameConfig from the upgrade
echo -e "${GREEN}Extracting new AdminCap and GameConfig...${NC}"

# Get new AdminCap (transferred to sender)
NEW_ADMIN_CAP=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType and (.objectType | contains("AdminCap"))) | .objectId')

# Get new GameConfig (shared object)
NEW_GAME_CONFIG=$(echo "$PUBLISH_OUTPUT" | jq -r '.objectChanges[] | select(.objectType and (.objectType | contains("GameConfig"))) | .objectId')

# Validate extracted objects
if [ -z "$NEW_ADMIN_CAP" ] || [ "$NEW_ADMIN_CAP" = "null" ]; then
    echo -e "${RED}Failed to extract new AdminCap${NC}"
    exit 1
fi

if [ -z "$NEW_GAME_CONFIG" ] || [ "$NEW_GAME_CONFIG" = "null" ]; then
    echo -e "${RED}Failed to extract new GameConfig${NC}"
    exit 1
fi

echo -e "${GREEN}New AdminCap: $NEW_ADMIN_CAP${NC}"
echo -e "${GREEN}New GameConfig: $NEW_GAME_CONFIG${NC}"

# Get the transaction digest
TX_DIGEST=$(echo "$PUBLISH_OUTPUT" | jq -r '.digest')

# Create backup of old config
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Update config with new package and objects info
UPDATED_CONFIG=$(jq \
    --arg newPackageId "$NEW_PACKAGE_ID" \
    --arg oldPackageId "$PACKAGE_ID" \
    --arg newAdminCap "$NEW_ADMIN_CAP" \
    --arg oldAdminCap "$OLD_ADMIN_CAP" \
    --arg newGameConfig "$NEW_GAME_CONFIG" \
    --arg oldGameConfig "$OLD_GAME_CONFIG" \
    --arg upgradeDate "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg txDigest "$TX_DIGEST" \
    '.packageId = $newPackageId |
    .adminCap = $newAdminCap |
    .gameConfig = $newGameConfig |
    .upgrades += [{
        "fromPackage": $oldPackageId,
        "toPackage": $newPackageId,
        "oldAdminCap": $oldAdminCap,
        "newAdminCap": $newAdminCap,
        "oldGameConfig": $oldGameConfig,
        "newGameConfig": $newGameConfig,
        "transaction": $txDigest,
        "date": $upgradeDate
    }]' "$CONFIG_FILE")

echo "$UPDATED_CONFIG" > "$CONFIG_FILE"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Package Upgrade Complete!${NC}"
echo -e "  Old Package: ${YELLOW}$PACKAGE_ID${NC}"
echo -e "  New Package: ${YELLOW}$NEW_PACKAGE_ID${NC}"
echo -e "  Old AdminCap: ${YELLOW}$OLD_ADMIN_CAP${NC}"
echo -e "  New AdminCap: ${YELLOW}$NEW_ADMIN_CAP${NC}"
echo -e "  Old GameConfig: ${YELLOW}$OLD_GAME_CONFIG${NC}"
echo -e "  New GameConfig: ${YELLOW}$NEW_GAME_CONFIG${NC}"
echo -e "  Transaction: ${YELLOW}$TX_DIGEST${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${GREEN}Upgrade Benefits:${NC}"
echo -e "  ✅ Package ID updated to new version"
echo -e "  ✅ New AdminCap and GameConfig extracted"
echo -e "  ✅ Admin functions now work with upgraded package"
echo -e "  ✅ Configuration automatically updated"
echo -e "  ✅ Old objects backed up in upgrade history"

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  - Update your frontend/client to use the new package ID"
echo -e "  - Test admin functions: make status NETWORK=$NETWORK"
echo -e "  - Existing games continue with old package (unaffected)"
echo -e "  - New games will use the upgraded package"

echo -e "${GREEN}Upgrade complete!${NC}" 