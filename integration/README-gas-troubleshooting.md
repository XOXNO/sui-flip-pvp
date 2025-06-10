# SUI Coin Flip Gas & Balance Troubleshooting

## Common Gas Errors and Solutions

### 1. "No gas tokens" or "Insufficient balance"

This happens when you don't have enough SUI tokens to pay for gas fees.

#### Solution A: Get SUI from Faucet (Testnet/Devnet)

**For Testnet:**
```bash
curl --location --request POST 'https://faucet.testnet.sui.io/gas' \
--header 'Content-Type: application/json' \
--data-raw '{
    "FixedAmountRequest": {
        "recipient": "YOUR_WALLET_ADDRESS"
    }
}'
```

**For Devnet:**
```bash
curl --location --request POST 'https://faucet.devnet.sui.io/gas' \
--header 'Content-Type: application/json' \
--data-raw '{
    "FixedAmountRequest": {
        "recipient": "YOUR_WALLET_ADDRESS"
    }
}'
```

**Using SUI CLI:**
```bash
# For testnet
sui client faucet --address YOUR_WALLET_ADDRESS

# For devnet  
sui client faucet --address YOUR_WALLET_ADDRESS --url https://faucet.devnet.sui.io/gas
```

**Web Faucets:**
- Testnet: https://docs.sui.io/guides/developer/getting-started/get-coins
- Devnet: https://docs.sui.io/guides/developer/getting-started/get-coins

#### Solution B: Check Your Balance

Use the "Debug Balance" button in the UI or run:

```typescript
const balance = await sdk.getUserBalance(userAddress);
console.log('Balance:', CoinFlipSDK.mistToSui(balance), 'SUI');

const detailedBalance = await sdk.getDetailedBalance(userAddress);
console.log('Detailed balance:', detailedBalance);
```

### 2. Gas Estimates

The SDK automatically reserves gas for different operations:

- **Create Game**: 0.01 SUI
- **Join Game**: 0.015 SUI  
- **Cancel Game**: 0.005 SUI

### 3. Total Requirements

When creating a game with 0.1 SUI bet:
- Bet: 0.1 SUI
- Gas: 0.01 SUI
- **Total needed**: 0.11 SUI

### 4. Pre-Transaction Checking

The SDK now automatically checks if you have enough balance:

```typescript
const affordability = await sdk.canAffordTransaction(userAddress, betAmount, 'create');

if (!affordability.canAfford) {
  console.log('Shortfall:', CoinFlipSDK.mistToSui(affordability.shortfall!), 'SUI');
}
```

### 5. Debug Information

Use the debug function for detailed analysis:

```typescript
const debug = await sdk.debugTransactionRequirements(userAddress, betAmount, 'create');
console.log('Debug info:', debug);
```

This provides:
- Current balance
- Required amount
- Gas estimates
- Coin count
- Helpful suggestions

## Quick Fixes

### If you have 0 SUI:
1. Go to SUI faucet: https://docs.sui.io/guides/developer/getting-started/get-coins
2. Enter your wallet address
3. Request tokens
4. Wait 1-2 minutes for tokens to arrive

### If you have some SUI but not enough:
1. Reduce your bet amount
2. Get more SUI from faucet
3. Check the "Debug Balance" button for exact requirements

### If you have many small coin objects:
The transaction might fail if you have too many small coins. Consider:
1. Using a wallet to merge coins
2. Making smaller bets first
3. Waiting for automatic coin merging

## Network-Specific Issues

### Testnet
- Faucet limit: Usually 1-10 SUI per request
- Rate limited: Wait between requests
- Sometimes congested: Try again later

### Devnet
- More unstable than testnet
- Faster faucet refills
- May have occasional issues

### Mainnet
- You need real SUI tokens
- Buy from exchanges like Binance, Coinbase, etc.
- Much higher gas costs

## Error Messages Explained

| Error | Meaning | Solution |
|-------|---------|----------|
| "No gas tokens" | 0 SUI balance | Get SUI from faucet |
| "Insufficient balance" | Not enough for bet + gas | Reduce bet or get more SUI |
| "Gas budget exceeded" | Transaction too complex | Lower gas estimate or simplify |
| "Coin not found" | Coin was spent/moved | Refresh and try again |

## Best Practices

1. **Always keep some SUI for gas** - Don't bet your entire balance
2. **Start small** - Test with small amounts first
3. **Check balance before transactions** - Use the debug tools
4. **Wait for confirmations** - Don't spam transactions
5. **Use the right network** - Make sure you're on testnet/devnet for testing

## Getting Help

If you're still having issues:

1. Check the browser console for detailed error messages
2. Use the "Debug Balance" button to get detailed info
3. Verify you're on the correct network (testnet/devnet/mainnet)
4. Make sure your wallet is connected and unlocked
5. Try refreshing the page and reconnecting wallet

## Emergency Recovery

If you're completely stuck:

1. **Create a new wallet address**
2. **Get fresh SUI from faucet**
3. **Start with small test amounts**
4. **Gradually increase once working**

Remember: On testnet/devnet, SUI tokens are free and unlimited from faucets! 