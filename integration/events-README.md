# SUI Coin Flip Real-Time Events

This system provides real-time WebSocket connections to track your coin flip game events as they happen on the SUI blockchain.

## 🚀 Quick Start

### 1. Basic Hook Usage

```tsx
import { useCoinFlipEvents } from './useCoinFlipEvents';

function MyComponent() {
  const {
    isConnected,
    recentEvents,
    gameCreatedEvents,
    gameJoinedEvents,
    gameCancelledEvents
  } = useCoinFlipEvents({
    packageId: 'YOUR_PACKAGE_ID',
    network: 'testnet',
    onGameCreated: (event) => {
      console.log('🎮 New game!', event);
      // Trigger animations, notifications, etc.
    },
    onGameJoined: (event) => {
      console.log('🎯 Game completed!', event);
      // Show winner celebration
    },
    onGameCancelled: (event) => {
      console.log('❌ Game cancelled!', event);
    }
  });

  return (
    <div>
      <p>Connection: {isConnected ? '🟢 Connected' : '🔴 Disconnected'}</p>
      <p>Recent events: {recentEvents.length}</p>
    </div>
  );
}
```

### 2. Advanced Usage with Manual Control

```tsx
const events = useCoinFlipEvents({
  packageId: 'YOUR_PACKAGE_ID',
  network: 'testnet',
  autoConnect: false, // Manual control
});

// Connect/disconnect manually
const handleConnect = () => events.connect();
const handleDisconnect = () => events.disconnect();

// Get historical events
const loadHistory = async () => {
  const created = await events.getHistoricalEvents('GameCreated', 100);
  const completed = await events.getHistoricalEvents('GameJoined', 100);
};

// Get events for specific game
const getGameHistory = async (gameId: string) => {
  const gameEvents = await events.getGameEvents(gameId);
  console.log('Game timeline:', gameEvents);
};
```

## 📡 Event Types

### GameCreated
```typescript
{
  game_id: string;
  creator: string;
  bet_amount: string;     // In MIST
  creator_choice: boolean; // true = heads, false = tails
  created_at: string;
}
```

### GameJoined (Game Completed)
```typescript
{
  game_id: string;
  joiner: string;
  winner: string;
  loser: string;
  total_pot: string;      // In MIST
  winner_payout: string;  // In MIST
  fee_collected: string;  // In MIST
  coin_flip_result: boolean; // true = heads, false = tails
}
```

### GameCancelled
```typescript
{
  game_id: string;
  creator: string;
  refund_amount: string;  // In MIST
}
```

## 🎯 Use Cases

### Live Notifications
```tsx
onGameCreated: (event) => {
  showToast(`🎮 New game: ${mistToSui(event.bet_amount)} SUI`);
  playSound('game-created');
},
onGameJoined: (event) => {
  if (event.winner === currentUserAddress) {
    showConfetti();
    playSound('victory');
  }
}
```

### Game Statistics Dashboard
```tsx
const stats = {
  totalGames: gameCreatedEvents.length,
  completedGames: gameJoinedEvents.length,
  cancelledGames: gameCancelledEvents.length,
  totalVolume: gameJoinedEvents.reduce((sum, game) => 
    sum + BigInt(game.total_pot), BigInt(0)
  )
};
```

### Real-time Game List
```tsx
const activeGames = gameCreatedEvents.filter(created => 
  !gameJoinedEvents.some(joined => joined.game_id === created.game_id) &&
  !gameCancelledEvents.some(cancelled => cancelled.game_id === created.game_id)
);
```

## 🛠 Network Configuration

```typescript
const networks = {
  mainnet: 'wss://fullnode.mainnet.sui.io:443',
  testnet: 'wss://fullnode.testnet.sui.io:443', 
  devnet: 'wss://fullnode.devnet.sui.io:443',
  localnet: 'ws://localhost:9000'
};
```

## 📊 Event Filtering

```typescript
// Filter events by user
const userGames = recentEvents.filter(event => 
  event.data.creator === userAddress || 
  event.data.joiner === userAddress
);

// Filter high-value games
const highValueGames = gameCreatedEvents.filter(event =>
  BigInt(event.bet_amount) >= BigInt('1000000000') // >= 1 SUI
);

// Filter by time range
const recentGames = recentEvents.filter(event =>
  event.timestamp > Date.now() - (60 * 60 * 1000) // Last hour
);
```

## 🔧 Error Handling

```tsx
const events = useCoinFlipEvents({
  packageId: 'YOUR_PACKAGE_ID',
  network: 'testnet',
  onGameCreated: (event) => {
    try {
      // Your game logic
    } catch (error) {
      console.error('Error handling game created:', error);
    }
  }
});

// Check for connection errors
if (events.error) {
  console.error('Connection error:', events.error);
  // Maybe show reconnect button
}
```

## 🎨 Animation Ideas

```tsx
// Coin flip animation on game complete
onGameJoined: (event) => {
  const result = event.coin_flip_result ? 'heads' : 'tails';
  triggerCoinFlipAnimation(result);
  
  if (event.winner === currentUser) {
    triggerVictoryAnimation();
  }
};

// Pulse effect for new games
onGameCreated: (event) => {
  const gameElement = document.getElementById(`game-${event.game_id}`);
  gameElement?.classList.add('animate-pulse-glow');
};
```

## 📝 Notes

- Events are automatically parsed from SUI's WebSocket stream
- Connection is managed automatically with auto-reconnect
- Historical events can be queried for initial state
- All amounts are in MIST (1 SUI = 1,000,000,000 MIST)
- Use `CoinFlipSDK.mistToSui()` to convert for display 