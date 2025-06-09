# SUI Coin Flip Game

A secure and fully tested coin flip game smart contract for the SUI blockchain. Players can create games with SUI bets and others can join to flip for the win using native SUI randomness.

## Features

- 🎲 **Provably Fair**: Uses SUI's native randomness beacon for true randomness
- 🔒 **Secure**: Comprehensive security checks and reentrancy protection
- ⚡ **Efficient**: Optimized gas usage and modular design
- 🛠 **Admin Controls**: Pause/unpause, fee management, bet limits
- 🧪 **Well Tested**: 29 comprehensive tests covering all scenarios
- 📊 **Event Tracking**: Clean events for easy backend integration

## Quick Start

### Prerequisites

- [SUI CLI](https://docs.sui.io/build/install) installed and configured
- `jq` for JSON processing
- `bc` for calculations (usually pre-installed on macOS/Linux)

### 1. Build and Test

```bash
# Build the contract
make build

# Run all tests
make test
```

### 2. Deploy

```bash
# Deploy to testnet
make deploy NETWORK=testnet

# Deploy to mainnet
make deploy NETWORK=mainnet
```

### 3. Check Status

```bash
# Check deployment status
make status NETWORK=testnet
```

## Contract Architecture

### Core Objects

- **`Game`**: Individual coin flip game instances
- **`GameConfig`**: Global configuration and treasury (shared object)
- **`AdminCap`**: Admin capability for contract management

### Key Functions

- **`create_game`**: Create a new coin flip game
- **`join_game`**: Join an existing game and trigger the coin flip
- **`cancel_game`**: Cancel a pending game and get refund

## Admin Management

### Fee Management

```bash
# Set fee to 2.5% (250 basis points)
make set-fee FEE_BPS=250 NETWORK=testnet

# Set fee to 1% (100 basis points)
make set-fee FEE_BPS=100 NETWORK=testnet
```

### Bet Limits

```bash
# Set limits: 0.01 SUI min, 1000 SUI max
make update-limits MIN_BET=10000000 MAX_BET=1000000000000 NETWORK=testnet

# Set limits: 0.1 SUI min, 100 SUI max
make update-limits MIN_BET=100000000 MAX_BET=100000000000 NETWORK=testnet
```

### Pause/Unpause

```bash
# Pause all game operations
make pause NETWORK=testnet

# Resume game operations
make unpause NETWORK=testnet
```

### Fee Withdrawal

```bash
# Withdraw all accumulated fees
make withdraw-fees NETWORK=testnet
```

## Available Commands

### Build & Deploy
```bash
make build           # Build the Move package
make test            # Run all tests
make deploy          # Deploy the contract
make upgrade         # Deploy new package version
make clean           # Clean build artifacts
```

### Admin Operations
```bash
make set-fee         # Set game fee percentage
make update-limits   # Update bet limits
make pause           # Pause contract operations
make unpause         # Resume contract operations
make withdraw-fees   # Withdraw accumulated fees
```

### Utilities
```bash
make status          # Check deployment status
make examples        # Show usage examples
make help            # Show all commands
```

## Configuration

### Network Configuration

The Makefile automatically configures RPC URLs and gas budgets based on the network:

- **Testnet**: `https://fullnode.testnet.sui.io:443`
- **Mainnet**: `https://fullnode.mainnet.sui.io:443`

### Environment Variables

```bash
NETWORK=testnet                    # Target network (testnet/mainnet)
FEE_BPS=250                       # Fee in basis points (250 = 2.5%)
MIN_BET=10000000                  # Min bet in MIST (0.01 SUI)
MAX_BET=1000000000000             # Max bet in MIST (1000 SUI)
GAS_BUDGET=200000000              # Gas budget for transactions
```

## Deployment Structure

After deployment, configuration is stored in:

```
deployments/
├── testnet/
│   └── config.json
└── mainnet/
    └── config.json
```

### Sample Configuration

```json
{
  "network": "testnet",
  "packageId": "0x...",
  "adminCap": "0x...",
  "gameConfig": "0x...",
  "deploymentTx": "0x...",
  "deployedAt": "2024-01-01T00:00:00Z",
  "deployer": "0x...",
  "contractState": {
    "isPaused": false,
    "feePercentage": 250,
    "minBetAmount": 10000000,
    "maxBetAmount": 1000000000000,
    "treasuryBalance": 0
  }
}
```

## Common Usage Examples

### Development Workflow

```bash
# 1. Build and test
make build test

# 2. Deploy to testnet
make deploy NETWORK=testnet

# 3. Check status
make status NETWORK=testnet

# 4. Set fee to 2.5%
make set-fee FEE_BPS=250 NETWORK=testnet

# 5. Update limits for testing (0.001-10 SUI)
make update-limits MIN_BET=1000000 MAX_BET=10000000000 NETWORK=testnet
```

### Production Deployment

```bash
# 1. Final testing
make test

# 2. Deploy to mainnet
make deploy NETWORK=mainnet

# 3. Set production fee (1%)
make set-fee FEE_BPS=100 NETWORK=mainnet

# 4. Set production limits (0.01-1000 SUI)
make update-limits MIN_BET=10000000 MAX_BET=1000000000000 NETWORK=mainnet

# 5. Verify status
make status NETWORK=mainnet
```

### Emergency Procedures

```bash
# Pause contract immediately
make pause NETWORK=mainnet

# Check current status
make status NETWORK=mainnet

# Resume when ready
make unpause NETWORK=mainnet
```

## Contract Constants

- **Fee Base**: 10,000 (100% = 10,000 basis points)
- **Default Fee**: 250 basis points (2.5%)
- **Min Bet**: 10,000,000 MIST (0.01 SUI)
- **Max Bet**: 1,000,000,000,000 MIST (1,000 SUI)

## Security Features

- ✅ **One-Time-Witness Pattern**: Ensures unique admin capability
- ✅ **Admin Validation**: All admin functions validate capability ownership
- ✅ **Reentrancy Protection**: Game state management prevents reentrancy
- ✅ **Input Validation**: Comprehensive parameter validation
- ✅ **Pause Mechanism**: Emergency pause for all operations
- ✅ **Bet Limits**: Configurable min/max bet amounts
- ✅ **Native Randomness**: Uses SUI's secure randomness beacon

## Testing

The contract includes 29 comprehensive tests covering:

- ✅ Game creation and joining
- ✅ Admin functions (pause, fees, limits)
- ✅ Error conditions and edge cases
- ✅ Security validations
- ✅ Event emissions

```bash
# Run all tests
make test

# Run specific test module
sui move test coin_flip_tests

# Run extended tests
sui move test coin_flip_extended_tests
```

## Troubleshooting

### Common Issues

1. **"Config not found"**: Run `make deploy` first
2. **"Transaction failed"**: Check gas budget and network connectivity
3. **"Permission denied"**: Ensure scripts are executable (`chmod +x scripts/*.sh`)
4. **"jq not found"**: Install jq (`brew install jq` on macOS)

### Debug Commands

```bash
# Check current active address
sui client active-address

# Check gas balance
sui client gas

# Check object details
sui client object <OBJECT_ID>

# View transaction details
sui client transaction <TX_DIGEST>
```

## Contract Integration

### Frontend Integration

Use the deployed package ID and GameConfig object ID from your deployment config:

```typescript
const PACKAGE_ID = "0x..."; // From config.json
const GAME_CONFIG = "0x..."; // From config.json

// Create game
await sui.moveCall({
  target: `${PACKAGE_ID}::coin_flip::create_game`,
  arguments: [bet_coin, choice, game_config, clock],
});

// Join game
await sui.moveCall({
  target: `${PACKAGE_ID}::coin_flip::join_game`,
  arguments: [game, bet_coin, game_config, random, clock],
});
```

### Event Monitoring

Listen for these events:

- `GameCreated`: New game created
- `GameJoined`: Game completed with results
- `GameCancelled`: Game cancelled by creator
- `ConfigUpdated`: Admin configuration changes

## Support

For issues or questions:

1. Check the [troubleshooting section](#troubleshooting)
2. Review test cases for usage examples
3. Check deployment logs in `deployments/<network>/`

## License

MIT License - see LICENSE file for details. 