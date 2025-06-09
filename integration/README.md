# SUI Coin Flip Game Integration SDK

This directory contains everything you need to integrate the SUI coin flip smart contract into your NextJS application.

## Files Overview

- `sui-coin-flip-sdk.ts` - Main SDK for interacting with the smart contract
- `example-usage.tsx` - Complete React component example
- `package.json` - Required dependencies
- `README.md` - This documentation

## Prerequisites

1. **SUI Wallet**: Users need a SUI wallet (Sui Wallet, Suiet, etc.)
2. **Testnet SUI**: For testing on testnet
3. **Contract Deployment**: Your contract must be deployed and you need:
   - Package ID
   - GameConfig object ID
   - (Optional) AdminCap object ID for admin functions

## Installation

### 1. Install Required Dependencies

```bash
npm install @mysten/sui.js @mysten/wallet-adapter-react @mysten/wallet-adapter-sui
```

### 2. Set Up Wallet Provider

In your NextJS `_app.tsx` or root component:

```tsx
import { WalletProvider } from '@mysten/wallet-adapter-react';
import '@mysten/wallet-adapter-react/style.css';

function MyApp({ Component, pageProps }) {
  return (
    <WalletProvider>
      <Component {...pageProps} />
    </WalletProvider>
  );
}

export default MyApp;
```

### 3. Configure Your Contract Details

Update the constants in both `sui-coin-flip-sdk.ts` and `example-usage.tsx`:

```typescript
// Replace with your actual deployment values
const PACKAGE_ID = '0x4bb85342890080a28c96a5fa6751110fdbe36c1dfe3f66f44dc497ffec60bd58';
const GAME_CONFIG_ID = '0x741f172d57cd0929fba3e7815dc90eff15657f415cb46ff9024d8a4c7fd6c7b0';
```

## SDK Usage

### Basic Setup

```typescript
import { CoinFlipSDK } from './sui-coin-flip-sdk';

const sdk = new CoinFlipSDK('testnet', PACKAGE_ID, GAME_CONFIG_ID);
```

### Creating a Game

```typescript
async function createGame(userAddress: string) {
  try {
    const betAmount = CoinFlipSDK.suiToMist('0.1'); // 0.1 SUI
    const choice = true; // true = heads, false = tails
    
    const tx = await sdk.createGame(userAddress, betAmount, choice);
    
    // Sign and execute with wallet
    const result = await wallet.signAndExecuteTransactionBlock({ 
      transactionBlock: tx 
    });
    
    console.log('Game created:', result);
  } catch (error) {
    console.error('Failed to create game:', error);
  }
}
```

### Joining a Game

```typescript
async function joinGame(userAddress: string, gameId: string) {
  try {
    // Get game details first
    const gameDetails = await sdk.getGameDetails(gameId);
    if (!gameDetails) throw new Error('Game not found');
    
    const tx = await sdk.joinGame(userAddress, gameId, gameDetails.betAmount);
    
    const result = await wallet.signAndExecuteTransactionBlock({ 
      transactionBlock: tx 
    });
    
    console.log('Joined game:', result);
  } catch (error) {
    console.error('Failed to join game:', error);
  }
}
```

### Fetching User Games

```typescript
async function getUserGames(userAddress: string) {
  try {
    const games = await sdk.getUserGames(userAddress);
    console.log('User games:', games);
    
    games.forEach(game => {
      console.log(`Game ${game.id}:`);
      console.log(`- Bet: ${CoinFlipSDK.mistToSui(game.betAmount)} SUI`);
      console.log(`- Choice: ${game.creatorChoice ? 'Heads' : 'Tails'}`);
      console.log(`- Status: ${game.isActive ? 'Active' : 'Finished'}`);
    });
  } catch (error) {
    console.error('Failed to get user games:', error);
  }
}
```

### Checking Contract Status

```typescript
async function checkContractStatus() {
  try {
    const config = await sdk.getGameConfig();
    console.log('Contract status:', {
      isPaused: config.isPaused,
      feePercentage: config.feePercentage / 100, // Convert to percentage
      minBet: CoinFlipSDK.mistToSui(config.minBetAmount),
      maxBet: CoinFlipSDK.mistToSui(config.maxBetAmount),
      treasuryBalance: CoinFlipSDK.mistToSui(config.treasuryBalance),
    });
  } catch (error) {
    console.error('Failed to check status:', error);
  }
}
```

## Admin Functions

If you have admin privileges (own the AdminCap), you can perform admin operations:

### Set Fee Percentage

```typescript
async function setFee(userAddress: string, newFeePercentage: number) {
  try {
    const adminCapId = await sdk.isAdmin(userAddress);
    if (!adminCapId) throw new Error('User is not admin');
    
    // Fee is in basis points (250 = 2.5%)
    const tx = await sdk.setFeePercentage(adminCapId, newFeePercentage);
    
    const result = await wallet.signAndExecuteTransactionBlock({ 
      transactionBlock: tx 
    });
    
    console.log('Fee updated:', result);
  } catch (error) {
    console.error('Failed to set fee:', error);
  }
}
```

### Update Bet Limits

```typescript
async function updateLimits(userAddress: string, minBet: string, maxBet: string) {
  try {
    const adminCapId = await sdk.isAdmin(userAddress);
    if (!adminCapId) throw new Error('User is not admin');
    
    const minBetMist = CoinFlipSDK.suiToMist(minBet);
    const maxBetMist = CoinFlipSDK.suiToMist(maxBet);
    
    const tx = await sdk.updateBetLimits(adminCapId, minBetMist, maxBetMist);
    
    const result = await wallet.signAndExecuteTransactionBlock({ 
      transactionBlock: tx 
    });
    
    console.log('Limits updated:', result);
  } catch (error) {
    console.error('Failed to update limits:', error);
  }
}
```

### Withdraw Accumulated Fees

```typescript
async function withdrawFees(userAddress: string) {
  try {
    const adminCapId = await sdk.isAdmin(userAddress);
    if (!adminCapId) throw new Error('User is not admin');
    
    const tx = await sdk.withdrawFees(adminCapId);
    
    const result = await wallet.signAndExecuteTransactionBlock({ 
      transactionBlock: tx 
    });
    
    console.log('Fees withdrawn:', result);
  } catch (error) {
    console.error('Failed to withdraw fees:', error);
  }
}
```

## Important System Objects

The SDK automatically handles these system objects:

- **Random Object**: `0x8` - Used for generating randomness
- **Clock Object**: `0x6` - Used for timestamps
- **SUI Coins**: `0x2::sui::SUI` - Native SUI currency

## Error Handling

The SDK includes comprehensive error handling:

```typescript
try {
  const tx = await sdk.createGame(userAddress, betAmount, choice);
  // Handle success
} catch (error) {
  if (error.message.includes('Insufficient SUI balance')) {
    // Handle insufficient balance
  } else if (error.message.includes('Game not found')) {
    // Handle game not found
  } else {
    // Handle other errors
  }
}
```

## Utility Functions

The SDK provides helpful utility functions:

```typescript
// Convert between SUI and MIST
const suiAmount = CoinFlipSDK.mistToSui('1000000000'); // '1'
const mistAmount = CoinFlipSDK.suiToMist('1.5'); // '1500000000'

// Format addresses for display
const formatted = CoinFlipSDK.formatAddress('0x1234...5678'); // '0x1234...5678'

// Check admin status
const adminCapId = await sdk.isAdmin(userAddress);
const isAdmin = adminCapId !== null;
```

## Event Listening

To listen for game events, you can use the SUI client directly:

```typescript
// Listen for game completion events
const eventFilter = {
  MoveEventType: `${PACKAGE_ID}::coin_flip::GameCompleted`
};

const subscription = sdk.client.subscribeEvent({
  filter: eventFilter,
  onMessage: (event) => {
    console.log('Game completed:', event);
    // Handle game completion
  }
});

// Unsubscribe when done
// subscription.unsubscribe();
```

## Security Considerations

1. **Validate Inputs**: Always validate user inputs before creating transactions
2. **Check Balances**: Verify users have sufficient SUI before transactions
3. **Handle Failures**: Implement proper error handling for all operations
4. **Rate Limiting**: Consider implementing rate limiting for game creation
5. **Admin Protection**: Secure admin functions and verify permissions

## Testing

Test your integration on testnet before mainnet:

1. Get testnet SUI from the faucet
2. Deploy your contract to testnet
3. Test all functions thoroughly
4. Monitor gas costs and optimize if needed

## Troubleshooting

### Common Issues

1. **"Insufficient SUI balance"**: User doesn't have enough SUI for the bet + gas
2. **"Game not found"**: Game ID is invalid or game was deleted
3. **"Transaction failed"**: Usually due to invalid parameters or insufficient gas
4. **"Object not found"**: GameConfig or other object IDs are incorrect

### Debug Mode

Enable debug logging:

```typescript
const sdk = new CoinFlipSDK('testnet', PACKAGE_ID, GAME_CONFIG_ID);

// Enable verbose logging
sdk.client.getEvents().then(events => {
  console.log('Recent events:', events);
});
```

## Production Deployment

For production deployment:

1. **Use Mainnet**: Change network to `'mainnet'`
2. **Update Object IDs**: Use your mainnet deployment IDs
3. **Monitor Performance**: Track transaction success rates
4. **Error Reporting**: Implement proper error reporting
5. **Analytics**: Track user interactions and game outcomes

## Support

If you encounter issues:

1. Check the console for detailed error messages
2. Verify all object IDs are correct
3. Ensure sufficient SUI balance for transactions
4. Test on testnet first before mainnet deployment

## Example Integration

See `example-usage.tsx` for a complete React component that demonstrates:

- Wallet connection
- Game creation and joining
- Admin functions
- Error handling
- User interface patterns

This example provides a solid foundation for building your own game interface. 