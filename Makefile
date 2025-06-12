# Coin Flip Game Makefile
# Supports deployment, upgrade, and admin operations on testnet and mainnet

# Default network is testnet
NETWORK ?= testnet
ADMIN_ADDRESS ?= $(shell sui client active-address)

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
	@echo "Usage: make [command] NETWORK=[testnet|mainnet]"
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
	@echo "  update-limits   - Update bet limits (MIN_BET=10000000 MAX_BET=1000000000000)"
	@echo "  update-max-games - Update max games per transaction (MAX_GAMES=100)"
	@echo "  update-treasury - Update treasury address (TREASURY_ADDRESS=<address>)"
	@echo "  add-token       - Add token to whitelist (TOKEN_TYPE=0x2::sui::SUI)"
	@echo "  remove-token    - Remove token from whitelist (TOKEN_TYPE=0x123::usdc::USDC)"
	@echo "  list-tokens     - List all whitelisted tokens"
	@echo "  pause           - Pause contract operations"
	@echo "  unpause         - Resume contract operations"
	@echo ""
	@echo "Development & Utility Commands:"
	@echo "  dev-setup       - Complete development setup (build + deploy)"
	@echo "  status          - Check deployment status on network"
	@echo ""
	@echo "Environment Variables:"
	@echo "  NETWORK         - Target network (testnet/mainnet)"
	@echo "  ADMIN_ADDRESS   - Admin wallet address"
	@echo "  GAS_BUDGET      - Gas budget for transactions"
	@echo "  FEE_BPS         - Fee in basis points (for set-fee command)"
	@echo "  MIN_BET         - Minimum bet amount in MIST (for update-limits)"
	@echo "  MAX_BET         - Maximum bet amount in MIST (for update-limits)"
	@echo "  TREASURY_ADDRESS - Treasury wallet address (for update-treasury)"
	@echo "  TOKEN_TYPE      - Token type for whitelist operations (0x2::sui::SUI)"

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
	@./scripts/deploy.sh $(NETWORK) $(RPC_URL) $(GAS_BUDGET)

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
	@echo "$(GREEN)Setting game fee to $(FEE_BPS) bps...$(NC)"
	@./scripts/admin/set_fee.sh $(NETWORK) $(FEE_BPS) $(RPC_URL) $(GAS_BUDGET)

# Admin function: Update bet limits
update-limits:
	@if [ -z "$(MIN_BET)" ] || [ -z "$(MAX_BET)" ]; then \
		echo "$(RED)Error: MIN_BET and MAX_BET not set. Usage: make update-limits MIN_BET=10000000 MAX_BET=1000000000000$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Updating bet limits to $(MIN_BET)-$(MAX_BET) MIST...$(NC)"
	@./scripts/admin/update_limits.sh $(NETWORK) $(MIN_BET) $(MAX_BET) $(RPC_URL) $(GAS_BUDGET)

# Admin function: Update max games per transaction
update-max-games:
	@if [ -z "$(MAX_GAMES)" ]; then \
		echo "$(RED)Error: MAX_GAMES not set. Usage: make update-max-games MAX_GAMES=100$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Updating max games per transaction to $(MAX_GAMES)...$(NC)"
	@./scripts/admin/update_max_games.sh $(NETWORK) $(MAX_GAMES) $(RPC_URL) $(GAS_BUDGET)

# Admin function: Update treasury address
update-treasury:
	@if [ -z "$(TREASURY_ADDRESS)" ]; then \
		echo "$(RED)Error: TREASURY_ADDRESS not set. Usage: make update-treasury TREASURY_ADDRESS=<address>$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Updating treasury address to $(TREASURY_ADDRESS)...$(NC)"
	@./scripts/admin/update_treasury_address.sh $(NETWORK) $(TREASURY_ADDRESS) $(RPC_URL) $(GAS_BUDGET)

# Admin function: Add token to whitelist
add-token:
	@if [ -z "$(TOKEN_TYPE)" ]; then \
		echo "$(RED)Error: TOKEN_TYPE not set. Usage: make add-token TOKEN_TYPE=0x2::sui::SUI$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Adding token $(TOKEN_TYPE) to whitelist...$(NC)"
	@./scripts/admin/add_token.sh $(NETWORK) $(TOKEN_TYPE) $(RPC_URL) $(GAS_BUDGET)

# Admin function: Remove token from whitelist
remove-token:
	@if [ -z "$(TOKEN_TYPE)" ]; then \
		echo "$(RED)Error: TOKEN_TYPE not set. Usage: make remove-token TOKEN_TYPE=0x123::usdc::USDC$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Removing token $(TOKEN_TYPE) from whitelist...$(NC)"
	@./scripts/admin/remove_token.sh $(NETWORK) $(TOKEN_TYPE) $(RPC_URL) $(GAS_BUDGET)

# Admin function: List whitelisted tokens
list-tokens:
	@echo "$(GREEN)Fetching whitelisted tokens on $(NETWORK)...$(NC)"
	@./scripts/admin/list_tokens.sh $(NETWORK) $(RPC_URL)

# Admin function: Pause contract
pause:
	@echo "$(GREEN)Pausing contract...$(NC)"
	@./scripts/admin/pause.sh $(NETWORK) $(RPC_URL) $(GAS_BUDGET)

# Admin function: Unpause contract
unpause:
	@echo "$(GREEN)Unpausing contract...$(NC)"
	@./scripts/admin/unpause.sh $(NETWORK) $(RPC_URL) $(GAS_BUDGET)

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
	@echo "$(YELLOW)Common Usage Examples:$(NC)"
	@echo ""
	@echo "Deploy to testnet:"
	@echo "  make deploy NETWORK=testnet"
	@echo ""
	@echo "Deploy to mainnet:"
	@echo "  make deploy NETWORK=mainnet"
	@echo ""
	@echo "Set fee to 2.5% (250 bps):"
	@echo "  make set-fee FEE_BPS=250 NETWORK=testnet"
	@echo ""
	@echo "Update bet limits (0.2 SUI min, 1000 SUI max):"
	@echo "  make update-limits MIN_BET=200000000 MAX_BET=1000000000000 NETWORK=testnet"
	@echo ""
	@echo "Update treasury address:"
	@echo "  make update-treasury TREASURY_ADDRESS=0x123...abc NETWORK=testnet"
	@echo ""
	@echo "Add USDC token to whitelist:"
	@echo "  make add-token TOKEN_TYPE=0x123::usdc::USDC NETWORK=testnet"
	@echo ""
	@echo "Remove token from whitelist:"
	@echo "  make remove-token TOKEN_TYPE=0x123::usdc::USDC NETWORK=testnet"
	@echo ""
	@echo "Pause contract:"
	@echo "  make pause NETWORK=testnet" 