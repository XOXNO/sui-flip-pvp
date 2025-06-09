/**
 * SUI Coin Flip Events WebSocket Listener
 * Real-time event tracking for game creation, joining, and completion
 */

import { SuiClient } from '@mysten/sui/client';
import { SuiEvent } from '@mysten/sui/client';

// Event type definitions based on your smart contract
export interface GameCreatedEvent {
  game_id: string;
  creator: string;
  bet_amount: string;
  creator_choice: boolean;
  created_at: string;
}

export interface GameJoinedEvent {
  game_id: string;
  joiner: string;
  winner: string;
  loser: string;
  total_pot: string;
  winner_payout: string;
  fee_collected: string;
  coin_flip_result: boolean;
}

export interface GameCancelledEvent {
  game_id: string;
  creator: string;
  refund_amount: string;
}

export type CoinFlipEventType = 'GameCreated' | 'GameJoined' | 'GameCancelled';

export interface ParsedCoinFlipEvent {
  type: CoinFlipEventType;
  data: GameCreatedEvent | GameJoinedEvent | GameCancelledEvent;
  rawEvent: SuiEvent;
  timestamp: number;
}

export interface EventListenerOptions {
  packageId: string;
  network: 'mainnet' | 'testnet' | 'devnet' | 'localnet';
  onGameCreated?: (event: GameCreatedEvent, rawEvent: SuiEvent) => void;
  onGameJoined?: (event: GameJoinedEvent, rawEvent: SuiEvent) => void;
  onGameCancelled?: (event: GameCancelledEvent, rawEvent: SuiEvent) => void;
  onError?: (error: Error) => void;
  onConnect?: () => void;
  onDisconnect?: () => void;
}

export class CoinFlipEventsListener {
  private client: SuiClient;
  private packageId: string;
  private subscriptions: Array<() => Promise<boolean>> = [];
  private isConnected: boolean = false;
  private options: EventListenerOptions;

  constructor(options: EventListenerOptions) {
    this.options = options;
    this.packageId = options.packageId;
    this.client = new SuiClient({ 
      url: this.getNetworkUrl(options.network) 
    });
  }

  private getNetworkUrl(network: string): string {
    const urls = {
      mainnet: 'wss://fullnode.mainnet.sui.io:443',
      testnet: 'wss://fullnode.testnet.sui.io:443',
      devnet: 'wss://fullnode.devnet.sui.io:443',
      localnet: 'ws://localhost:9000'
    };
    return urls[network as keyof typeof urls] || urls.testnet;
  }

  /**
   * Start listening to all coin flip events
   */
  async startListening(): Promise<void> {
    try {
      // Subscribe to GameCreated events
      const gameCreatedUnsubscribe = await this.client.subscribeEvent({
        filter: {
          MoveEventType: `${this.packageId}::coin_flip::GameCreated`
        },
        onMessage: (event) => this.handleGameCreatedEvent(event)
      });

      // Subscribe to GameJoined events  
      const gameJoinedUnsubscribe = await this.client.subscribeEvent({
        filter: {
          MoveEventType: `${this.packageId}::coin_flip::GameJoined`
        },
        onMessage: (event) => this.handleGameJoinedEvent(event)
      });

      // Subscribe to GameCancelled events
      const gameCancelledUnsubscribe = await this.client.subscribeEvent({
        filter: {
          MoveEventType: `${this.packageId}::coin_flip::GameCancelled`
        },
        onMessage: (event) => this.handleGameCancelledEvent(event)
      });

      this.subscriptions = [
        gameCreatedUnsubscribe,
        gameJoinedUnsubscribe,
        gameCancelledUnsubscribe
      ];

      this.isConnected = true;
      this.options.onConnect?.();
      
      console.log('✅ Started listening to coin flip events');
    } catch (error) {
      const err = error as Error;
      console.error('❌ Failed to start event listener:', err);
      this.options.onError?.(err);
    }
  }

  /**
   * Stop listening to events and cleanup subscriptions
   */
  async stopListening(): Promise<void> {
    try {
      await Promise.all(this.subscriptions.map(unsubscribe => unsubscribe()));
      this.subscriptions = [];
      this.isConnected = false;
      this.options.onDisconnect?.();
      console.log('🔌 Stopped listening to events');
    } catch (error) {
      console.error('❌ Error stopping event listener:', error);
    }
  }

  /**
   * Get connection status
   */
  getConnectionStatus(): boolean {
    return this.isConnected;
  }

  /**
   * Handle GameCreated events
   */
  private handleGameCreatedEvent(event: SuiEvent): void {
    try {
      const data = event.parsedJson as GameCreatedEvent;
      console.log('🎮 Game Created:', data);
      this.options.onGameCreated?.(data, event);
    } catch (error) {
      console.error('Error parsing GameCreated event:', error);
    }
  }

  /**
   * Handle GameJoined events (game completed)
   */
  private handleGameJoinedEvent(event: SuiEvent): void {
    try {
      const data = event.parsedJson as GameJoinedEvent;
      console.log('🎯 Game Joined/Completed:', data);
      this.options.onGameJoined?.(data, event);
    } catch (error) {
      console.error('Error parsing GameJoined event:', error);
    }
  }

  /**
   * Handle GameCancelled events
   */
  private handleGameCancelledEvent(event: SuiEvent): void {
    try {
      const data = event.parsedJson as GameCancelledEvent;
      console.log('❌ Game Cancelled:', data);
      this.options.onGameCancelled?.(data, event);
    } catch (error) {
      console.error('Error parsing GameCancelled event:', error);
    }
  }

  /**
   * Query historical events (for initial load)
   */
  async getHistoricalEvents(
    eventType: CoinFlipEventType,
    limit: number = 50
  ): Promise<SuiEvent[]> {
    try {
      const response = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::${eventType}`
        },
        limit,
        order: 'descending'
      });

      return response.data;
    } catch (error) {
      console.error(`Error fetching historical ${eventType} events:`, error);
      return [];
    }
  }

  /**
   * Get events for a specific game
   */
  async getGameEvents(gameId: string): Promise<ParsedCoinFlipEvent[]> {
    try {
      const allEvents: ParsedCoinFlipEvent[] = [];

      // Get all event types and filter by game_id
      const eventTypes: CoinFlipEventType[] = ['GameCreated', 'GameJoined', 'GameCancelled'];
      
      for (const eventType of eventTypes) {
        const events = await this.getHistoricalEvents(eventType, 100);
        
        const gameSpecificEvents = events
          .filter(event => {
            const data = event.parsedJson as any;
            return data.game_id === gameId;
          })
          .map(event => ({
            type: eventType,
            data: event.parsedJson as any,
            rawEvent: event,
            timestamp: parseInt(event.timestampMs || '0')
          }));

        allEvents.push(...gameSpecificEvents);
      }

      // Sort by timestamp
      return allEvents.sort((a, b) => a.timestamp - b.timestamp);
    } catch (error) {
      console.error('Error fetching game events:', error);
      return [];
    }
  }
}

export default CoinFlipEventsListener; 