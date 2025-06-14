#!/bin/bash

# Utility functions for Ledger operations
# Source this file in admin scripts to use these functions

# Function to auto-select gas coin from Ledger address
auto_select_gas_coin() {
    local ledger_addr=$1
    local gas_budget=$2
    
    echo -e "${GREEN}Auto-selecting gas coin for Ledger address: $ledger_addr${NC}" >&2
    
    # Get gas coins for the address
    local gas_output=$(sui client gas "$ledger_addr" --json 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$gas_output" ]; then
        echo -e "${RED}Failed to query gas coins for address: $ledger_addr${NC}" >&2
        return 1
    fi
    
    # Extract the first gas coin with sufficient balance
    local selected_gas=$(echo "$gas_output" | jq -r --arg budget "$gas_budget" '.[] | select(.mistBalance >= ($budget | tonumber)) | .gasCoinId' | head -1)
    
    if [ -z "$selected_gas" ] || [ "$selected_gas" = "null" ]; then
        echo -e "${RED}No gas coin found with sufficient balance (need $gas_budget MIST)${NC}" >&2
        echo -e "${YELLOW}Available gas coins:${NC}" >&2
        echo "$gas_output" | jq -r '.[] | "  \(.gasCoinId): \(.mistBalance) MIST"' 2>/dev/null || echo "  None found" >&2
        return 1
    fi
    
    echo -e "${GREEN}Selected gas coin: $selected_gas${NC}" >&2
    echo "$selected_gas"
}

# Function to handle Ledger mode validation and gas selection
setup_ledger_gas() {
    local ledger_mode=$1
    local ledger_address=$2
    local gas_object_id=$3
    local gas_budget=$4
    
    if [ "$ledger_mode" = "true" ]; then
        if [ -n "$ledger_address" ] && [ -z "$gas_object_id" ]; then
            # Auto-select gas coin from Ledger address
            gas_object_id=$(auto_select_gas_coin "$ledger_address" "$gas_budget")
            if [ $? -ne 0 ]; then
                echo -e "${RED}Failed to auto-select gas coin${NC}"
                return 1
            fi
        elif [ -z "$ledger_address" ] && [ -z "$gas_object_id" ]; then
            echo -e "${RED}Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true${NC}"
            return 1
        fi
        
        if [ -z "$gas_object_id" ]; then
            echo -e "${RED}Error: Could not determine gas object ID${NC}"
            return 1
        fi
        
        echo -e "${GREEN}Using gas object: $gas_object_id${NC}"
    fi
    
    # Export the gas object ID for use in the calling script
    export SELECTED_GAS_OBJECT_ID="$gas_object_id"
    return 0
}

# Function to show Ledger transaction output and instructions
show_ledger_instructions() {
    local operation=$1
    local tx_output=$2
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🔒 LEDGER TRANSACTION READY${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}Operation: $operation${NC}"
    echo -e "${YELLOW}Transaction Bytes:${NC}"
    echo "$tx_output"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo -e "1. Copy the transaction bytes above"
    echo -e "2. Go to: ${BLUE}https://multisig-toolkit.mystenlabs.com/offline-signer${NC}"
    echo -e "3. Paste transaction bytes and connect your Ledger"
    echo -e "4. Sign the transaction to get the signature"
    echo -e "5. Go to: ${BLUE}https://multisig-toolkit.mystenlabs.com/execute-transaction${NC}"
    echo -e "6. Paste transaction bytes + signature and execute"
    echo -e "7. Copy the transaction digest from the result"
    echo -e "${GREEN}========================================${NC}"
} 