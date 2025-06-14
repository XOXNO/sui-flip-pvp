# Coin Flip Game Makefile
# Supports deployment, upgrade, and admin operations on testnet and mainnet

# Load environment configuration if it exists
-include sui-flip.env

# Export all variables so they're available to scripts
export

# Default values (can be overridden by sui-flip.env or command line)
NETWORK ?= testnet
LEDGER_MODE ?= false
LEDGER_ADDRESS ?=
GAS_OBJECT_ID ?=

# Set ADMIN_ADDRESS if not already set
ifeq ($(ADMIN_ADDRESS),)
    ADMIN_ADDRESS := $(shell sui client active-address 2>/dev/null || echo "")
endif

# Network-specific configurations
ifeq ($(NETWORK), mainnet)
    RPC_URL = https://fullnode.mainnet.sui.io:443
    GAS_BUDGET = 200000000
else
    RPC_URL = https://fullnode.testnet.sui.io:443
    GAS_BUDGET = 200000000
endif

# Colors for output
GREEN = \033[0;32m
RED = \033[0;31m
YELLOW = \033[1;33m
NC = \033[0m # No Color

.PHONY: help build test deploy upgrade clean

help:
	@echo "Coin Flip Game Management Commands"
	@echo ""
	@echo "Usage: make [command] [parameters...]"
	@echo ""
	@echo "$(YELLOW)🚀 Quick Start with Ledger:$(NC)"
	@echo "  1. Edit sui-flip.env with your Ledger address"
	@echo "  2. Run: make deploy"
	@echo "  3. Follow Ledger signing instructions"
	@echo ""
	@echo "Build & Deploy Commands:"
	@echo "  build           - Build the Move package"
	@echo "  test            - Run all tests"
	@echo "  deploy          - Deploy the coin flip contract"
	@echo "  upgrade         - Upgrade existing deployment"
	@echo "  clean           - Clean build artifacts"
	@echo ""
	@echo "Admin Commands:"
	@echo "  set-fee         - Set game fee percentage (FEE_BPS=250)"
	@echo "  update-limits   - Update global bet limits (DEPRECATED, use per-token limits)"
	@echo "  update-max-games - Update max games per transaction (MAX_GAMES=100)"
	@echo "  update-treasury - Update treasury address (TREASURY_ADDRESS=<address>)"
	@echo "  add-token       - Add token with limits (TOKEN_TYPE=0x2::sui::SUI MIN_BET=100000000 MAX_BET=1000000000000)"
	@echo "  remove-token    - Remove token from whitelist (TOKEN_TYPE=0x123::usdc::USDC)"
	@echo "  update-token-limits - Update per-token limits (TOKEN_TYPE=0x2::sui::SUI MIN_BET=200000000 MAX_BET=500000000000)"
	@echo "  list-tokens     - List all whitelisted tokens"
	@echo "  pause           - Pause contract operations"
	@echo "  unpause         - Resume contract operations"
	@echo ""
	@echo "Configuration Commands:"
	@echo "  config-setup    - Create configuration from template"
	@echo "  config-show     - Show current configuration"
	@echo "  config-ledger   - Quick setup for Ledger usage"
	@echo ""
	@echo "Development & Utility Commands:"
	@echo "  dev-setup       - Complete development setup (build + deploy)"
	@echo "  status          - Check deployment status on network"
	@echo ""
	@echo "Environment Variables:"
	@echo "  NETWORK         - Target network (testnet/mainnet)"
	@echo "  ADMIN_ADDRESS   - Admin wallet address"
	@echo "  GAS_BUDGET      - Gas budget for transactions"
	@echo "  LEDGER_MODE     - Enable Ledger mode (true/false) - generates unsigned tx bytes"
	@echo "  LEDGER_ADDRESS  - Your Ledger wallet address (auto-selects gas coin when set)"
	@echo "  GAS_OBJECT_ID   - Specific gas object ID (optional, auto-selected if LEDGER_ADDRESS set)"
	@echo "  FEE_BPS         - Fee in basis points (for set-fee command)"
	@echo "  MIN_BET         - Minimum bet amount in token units (for update-limits and token operations)"
	@echo "  MAX_BET         - Maximum bet amount in token units (for update-limits and token operations)"
	@echo "  TREASURY_ADDRESS - Treasury wallet address (for update-treasury)"
	@echo "  TOKEN_TYPE      - Token type for whitelist operations (0x2::sui::SUI)"
	@echo "  MAX_GAMES       - Maximum games per transaction (for update-max-games)"

# Build the Move package
build:
	@echo "$(GREEN)Building Move package...$(NC)"
	sui move build

# Run all tests
test:
	@echo "$(GREEN)Running tests...$(NC)"
	sui move test

# Deploy the coin flip contract
deploy: build
	@echo "$(GREEN)Deploying to $(NETWORK)...$(NC)"
	@echo "Using RPC: $(RPC_URL)"
	@echo "Admin address: $(ADMIN_ADDRESS)"
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		echo "$(YELLOW)Usage 1 (auto gas): make deploy LEDGER_MODE=true LEDGER_ADDRESS=<your_address> NETWORK=$(NETWORK)$(NC)"; \
		echo "$(YELLOW)Usage 2 (manual gas): make deploy LEDGER_MODE=true GAS_OBJECT_ID=<gas_object_id> NETWORK=$(NETWORK)$(NC)"; \
		exit 1; \
	fi
	@./scripts/deploy.sh $(NETWORK) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Upgrade existing deployment
upgrade: build
	@echo "$(GREEN)Upgrading on $(NETWORK)...$(NC)"
	@./scripts/upgrade.sh $(NETWORK) $(RPC_URL) $(GAS_BUDGET)

# Admin function: Set game fee percentage
set-fee:
	@if [ -z "$(FEE_BPS)" ]; then \
		echo "$(RED)Error: FEE_BPS not set. Usage: make set-fee FEE_BPS=250$(NC)"; \
		exit 1; \
	fi
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Setting game fee to $(FEE_BPS) bps...$(NC)"
	@./scripts/admin/set_fee.sh $(NETWORK) $(FEE_BPS) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: Update bet limits
update-limits:
	@if [ -z "$(MIN_BET)" ] || [ -z "$(MAX_BET)" ]; then \
		echo "$(RED)Error: MIN_BET and MAX_BET not set. Usage: make update-limits MIN_BET=10000000 MAX_BET=1000000000000$(NC)"; \
		exit 1; \
	fi
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Updating bet limits to $(MIN_BET)-$(MAX_BET) MIST...$(NC)"
	@./scripts/admin/update_limits.sh $(NETWORK) $(MIN_BET) $(MAX_BET) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: Update max games per transaction
update-max-games:
	@if [ -z "$(MAX_GAMES)" ]; then \
		echo "$(RED)Error: MAX_GAMES not set. Usage: make update-max-games MAX_GAMES=100$(NC)"; \
		exit 1; \
	fi
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Updating max games per transaction to $(MAX_GAMES)...$(NC)"
	@./scripts/admin/update_max_games.sh $(NETWORK) $(MAX_GAMES) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: Update treasury address
update-treasury:
	@if [ -z "$(TREASURY_ADDRESS)" ]; then \
		echo "$(RED)Error: TREASURY_ADDRESS not set. Usage: make update-treasury TREASURY_ADDRESS=<address>$(NC)"; \
		exit 1; \
	fi
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Updating treasury address to $(TREASURY_ADDRESS)...$(NC)"
	@./scripts/admin/update_treasury_address.sh $(NETWORK) $(TREASURY_ADDRESS) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: Add token to whitelist with per-token limits
add-token:
	@if [ -z "$(TOKEN_TYPE)" ]; then \
		echo "$(RED)Error: TOKEN_TYPE not set. Usage: make add-token TOKEN_TYPE=0x2::sui::SUI MIN_BET=100000000 MAX_BET=1000000000000$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(MIN_BET)" ] || [ -z "$(MAX_BET)" ]; then \
		echo "$(RED)Error: MIN_BET and MAX_BET not set. Usage: make add-token TOKEN_TYPE=0x2::sui::SUI MIN_BET=100000000 MAX_BET=1000000000000$(NC)"; \
		exit 1; \
	fi
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Adding token $(TOKEN_TYPE) to whitelist...$(NC)"
	@./scripts/admin/add_token.sh $(NETWORK) $(TOKEN_TYPE) $(MIN_BET) $(MAX_BET) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: Remove token from whitelist
remove-token:
	@if [ -z "$(TOKEN_TYPE)" ]; then \
		echo "$(RED)Error: TOKEN_TYPE not set. Usage: make remove-token TOKEN_TYPE=0x123::usdc::USDC$(NC)"; \
		exit 1; \
	fi
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Removing token $(TOKEN_TYPE) from whitelist...$(NC)"
	@./scripts/admin/remove_token.sh $(NETWORK) $(TOKEN_TYPE) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: Update per-token bet limits
update-token-limits:
	@if [ -z "$(TOKEN_TYPE)" ]; then \
		echo "$(RED)Error: TOKEN_TYPE not set. Usage: make update-token-limits TOKEN_TYPE=0x2::sui::SUI MIN_BET=100000000 MAX_BET=1000000000000$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(MIN_BET)" ] || [ -z "$(MAX_BET)" ]; then \
		echo "$(RED)Error: MIN_BET and MAX_BET not set. Usage: make update-token-limits TOKEN_TYPE=0x2::sui::SUI MIN_BET=100000000 MAX_BET=1000000000000$(NC)"; \
		exit 1; \
	fi
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Updating bet limits for token $(TOKEN_TYPE)...$(NC)"
	@./scripts/admin/update_token_limits.sh $(NETWORK) $(TOKEN_TYPE) $(MIN_BET) $(MAX_BET) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: List whitelisted tokens
list-tokens:
	@echo "$(GREEN)Fetching whitelisted tokens on $(NETWORK)...$(NC)"
	@./scripts/admin/list_tokens.sh $(NETWORK) $(RPC_URL)

# Admin function: Pause contract
pause:
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Pausing contract...$(NC)"
	@./scripts/admin/pause.sh $(NETWORK) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Admin function: Unpause contract
unpause:
	@if [ "$(LEDGER_MODE)" = "true" ] && [ -z "$(LEDGER_ADDRESS)" ] && [ -z "$(GAS_OBJECT_ID)" ]; then \
		echo "$(RED)Error: Either LEDGER_ADDRESS or GAS_OBJECT_ID is required when LEDGER_MODE=true$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Unpausing contract...$(NC)"
	@./scripts/admin/unpause.sh $(NETWORK) $(RPC_URL) $(GAS_BUDGET) $(LEDGER_MODE) $(LEDGER_ADDRESS) $(GAS_OBJECT_ID)

# Configuration Commands
config-setup:
	@if [ ! -f sui-flip.env ]; then \
		cp sui-flip.env.template sui-flip.env; \
		echo "$(GREEN)Created sui-flip.env from template$(NC)"; \
		echo "$(YELLOW)Edit sui-flip.env with your settings before using make commands$(NC)"; \
	else \
		echo "$(YELLOW)sui-flip.env already exists$(NC)"; \
	fi

config-show:
	@echo "$(GREEN)Current Configuration:$(NC)"
	@echo "  NETWORK: $(NETWORK)"
	@echo "  LEDGER_MODE: $(LEDGER_MODE)"
	@echo "  LEDGER_ADDRESS: $(LEDGER_ADDRESS)"
	@echo "  GAS_BUDGET: $(GAS_BUDGET)"
	@echo "  ADMIN_ADDRESS: $(ADMIN_ADDRESS)"
	@if [ -f sui-flip.env ]; then \
		echo "$(GREEN)Configuration file: sui-flip.env exists$(NC)"; \
	else \
		echo "$(YELLOW)Configuration file: sui-flip.env not found$(NC)"; \
	fi

config-ledger:
	@if [ -z "$(LEDGER_ADDRESS_INPUT)" ]; then \
		echo "$(RED)Usage: make config-ledger LEDGER_ADDRESS_INPUT=<your_ledger_address>$(NC)"; \
		echo "$(YELLOW)Example: make config-ledger LEDGER_ADDRESS_INPUT=0x123...abc$(NC)"; \
		exit 1; \
	fi
	@cp sui-flip.env.template sui-flip.env
	@sed -i.backup 's/LEDGER_ADDRESS=.*/LEDGER_ADDRESS=$(LEDGER_ADDRESS_INPUT)/' sui-flip.env
	@rm -f sui-flip.env.backup
	@echo "$(GREEN)Ledger configuration created!$(NC)"
	@echo "  LEDGER_MODE: true"
	@echo "  LEDGER_ADDRESS: $(LEDGER_ADDRESS_INPUT)"
	@echo "  NETWORK: testnet"
	@echo "$(GREEN)Ready to use: make deploy$(NC)"

# Clean build artifacts
clean:
	@echo "$(GREEN)Cleaning build artifacts...$(NC)"
	rm -rf build/
	@echo "$(GREEN)Clean complete!$(NC)"

# Development helpers
dev-setup: build deploy
	@echo "$(GREEN)Development setup complete!$(NC)"

# Check deployment status
status:
	@echo "$(GREEN)Checking deployment status on $(NETWORK)...$(NC)"
	@./scripts/status.sh $(NETWORK) $(RPC_URL)

# Examples with common values
examples:
	@echo "$(YELLOW)📋 Usage Examples:$(NC)"
	@echo ""
	@echo "$(GREEN)🚀 Quick Start with Ledger (.env method):$(NC)"
	@echo "  1. Setup: make config-ledger LEDGER_ADDRESS_INPUT=0x123...abc"
	@echo "  2. Deploy: make deploy"
	@echo "  3. Admin: make set-fee FEE_BPS=250"
	@echo ""
	@echo "$(GREEN)📝 Regular Commands (using sui-flip.env config):$(NC)"
	@echo "  make deploy                    # Deploy to configured network"
	@echo "  make set-fee FEE_BPS=250      # Set 2.5% fee"
	@echo "  make update-limits MIN_BET=200000000 MAX_BET=1000000000000  # DEPRECATED"
	@echo "  make pause                     # Pause contract"
	@echo "  make unpause                   # Resume operations"
	@echo "  make add-token TOKEN_TYPE=0x2::sui::SUI MIN_BET=100000000 MAX_BET=1000000000000"
	@echo "  make add-token TOKEN_TYPE=0x123::usdc::USDC MIN_BET=1000000 MAX_BET=10000000"
	@echo "  make update-token-limits TOKEN_TYPE=0x2::sui::SUI MIN_BET=200000000 MAX_BET=500000000000"
	@echo ""
	@echo "$(GREEN)⚙️ Configuration Management:$(NC)"
	@echo "  make config-show              # View current settings"
	@echo "  make config-setup             # Create config from template"
	@echo "  make config-ledger LEDGER_ADDRESS_INPUT=0x123...abc"
	@echo ""
	@echo "$(GREEN)🔧 Override Parameters:$(NC)"
	@echo "  make deploy NETWORK=mainnet              # Override network"
	@echo "  make deploy LEDGER_MODE=false            # Use CLI wallet"
	@echo "  make set-fee FEE_BPS=500 NETWORK=mainnet # Multiple overrides"
	@echo ""
	@echo "$(GREEN)🏗️ Development:$(NC)"
	@echo "  make build test               # Build and test"
	@echo "  make dev-setup               # Build + deploy"
	@echo "  make status                  # Check deployment status" 