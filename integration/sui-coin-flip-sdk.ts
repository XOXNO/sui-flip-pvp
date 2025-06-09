/**
 * SUI Coin Flip Game SDK
 * TypeScript module for integrating with the SUI coin flip smart contract
 * 
 * Usage:
 * import { CoinFlipSDK } from './sui-coin-flip-sdk';
 * const sdk = new CoinFlipSDK('testnet', PACKAGE_ID, GAME_CONFIG_ID);
 */

import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';

// Types for the coin flip game
export interface GameInfo {
  id: string;
  creator: string;
  betAmount: string;
  creatorChoice: boolean; // true for heads, false for tails
  isActive: boolean;
  createdAt: string;
}

export interface GameConfig {
  id: string;
  feePercentage: number;
  minBetAmount: string;
  maxBetAmount: string;
  isPaused: boolean;
  treasuryBalance: string;
}

export interface CoinFlipEvent {
  gameId: string;
  winner: string;
  loser: string;
  totalPot: string;
  winnerPayout: string;
  feeCollected: string;
  coinFlipResult: boolean;
}

export type Network = 'mainnet' | 'testnet' | 'devnet' | 'localnet';

export class CoinFlipSDK {
  private client: SuiClient;
  private packageId: string;
  private gameConfigId: string;
  private network: Network;

  constructor(network: Network, packageId: string, gameConfigId: string) {
    this.network = network;
    this.packageId = packageId;
    this.gameConfigId = gameConfigId;
    this.client = new SuiClient({ url: getFullnodeUrl(network) });
  }

  // ========================================
  // SYSTEM OBJECTS & UTILITIES
  // ========================================

  /**
   * Get the Random object (system object for randomness)
   */
  async getRandomObject(): Promise<string> {
    try {
      // Random is a system object at a fixed address
      const RANDOM_OBJECT_ID = '0x8';
      return RANDOM_OBJECT_ID;
    } catch (error) {
      throw new Error(`Failed to get Random object: ${error}`);
    }
  }

  /**
   * Get the Clock object (system object for timestamps)
   */
  async getClockObject(): Promise<string> {
    try {
      // Clock is a system object at a fixed address
      const CLOCK_OBJECT_ID = '0x6';
      return CLOCK_OBJECT_ID;
    } catch (error) {
      throw new Error(`Failed to get Clock object: ${error}`);
    }
  }

  /**
   * Get GameConfig object details
   */
  async getGameConfig(): Promise<GameConfig> {
    try {
      const response = await this.client.getObject({
        id: this.gameConfigId,
        options: { showContent: true }
      });

      if (!response.data?.content || response.data.content.dataType !== 'moveObject') {
        throw new Error('Invalid GameConfig object');
      }

      const fields = (response.data.content as any).fields;
      
      return {
        id: this.gameConfigId,
        feePercentage: parseInt(fields.fee_percentage),
        minBetAmount: fields.min_bet_amount,
        maxBetAmount: fields.max_bet_amount,
        isPaused: fields.is_paused,
        treasuryBalance: fields.treasury_balance
      };
    } catch (error) {
      throw new Error(`Failed to get GameConfig: ${error}`);
    }
  }

  /**
   * Get user's SUI coins for betting
   */
  async getUserCoins(userAddress: string, amount?: string): Promise<string[]> {
    try {
      const coins = await this.client.getCoins({
        owner: userAddress,
        coinType: '0x2::sui::SUI',
      });

      if (amount) {
        // Find coins that can cover the amount
        let totalValue = BigInt(0);
        const selectedCoins: string[] = [];
        
        for (const coin of coins.data) {
          selectedCoins.push(coin.coinObjectId);
          totalValue += BigInt(coin.balance);
          
          if (totalValue >= BigInt(amount)) {
            break;
          }
        }
        
        if (totalValue < BigInt(amount)) {
          throw new Error(`Insufficient SUI balance. Need ${amount}, have ${totalValue}`);
        }
        
        return selectedCoins;
      }

      return coins.data.map(coin => coin.coinObjectId);
    } catch (error) {
      throw new Error(`Failed to get user coins: ${error}`);
    }
  }

  // ========================================
  // GAME INTERACTIONS
  // ========================================

  /**
   * Create a new coin flip game
   * @param userAddress - Address of the game creator
   * @param betAmount - Amount to bet in MIST (1 SUI = 1,000,000,000 MIST)
   * @param choice - true for heads, false for tails
   * @returns Transaction ready to be signed and executed
   */
  async createGame(
    userAddress: string, 
    betAmount: string, 
    choice: boolean
  ): Promise<Transaction> {
    try {
      const tx = new Transaction();
      
      // Get required objects
      const clockId = await this.getClockObject();
      const userCoins = await this.getUserCoins(userAddress, betAmount);
      
      // Merge coins if multiple are needed
      let betCoin: any;
      if (userCoins.length === 1) {
        betCoin = tx.object(userCoins[0]);
      } else {
        // Merge multiple coins
        const [primaryCoin, ...otherCoins] = userCoins;
        betCoin = tx.object(primaryCoin);
        
        if (otherCoins.length > 0) {
          tx.mergeCoins(betCoin, otherCoins.map(coin => tx.object(coin)));
        }
      }
      
      // Split exact amount for betting
      const [splitCoin] = tx.splitCoins(betCoin, [tx.pure.u64(betAmount)]);
      
      // Create the game
      tx.moveCall({
        target: `${this.packageId}::coin_flip::create_game`,
        arguments: [
          splitCoin,
          tx.pure.bool(choice),
          tx.object(this.gameConfigId),
          tx.object(clockId),
        ],
      });
      
      return tx;
    } catch (error) {
      throw new Error(`Failed to create game transaction: ${error}`);
    }
  }

  /**
   * Join an existing game
   * @param userAddress - Address of the player joining
   * @param gameId - ID of the game to join
   * @param betAmount - Amount to bet (should match game's bet amount)
   * @returns Transaction ready to be signed and executed
   */
  async joinGame(
    userAddress: string, 
    gameId: string, 
    betAmount: string
  ): Promise<Transaction> {
    try {
      const tx = new Transaction();
      
      // Get required objects
      const clockId = await this.getClockObject();
      const randomId = await this.getRandomObject();
      const userCoins = await this.getUserCoins(userAddress, betAmount);
      
      // Merge coins if multiple are needed
      let betCoin: any;
      if (userCoins.length === 1) {
        betCoin = tx.object(userCoins[0]);
      } else {
        const [primaryCoin, ...otherCoins] = userCoins;
        betCoin = tx.object(primaryCoin);
        
        if (otherCoins.length > 0) {
          tx.mergeCoins(betCoin, otherCoins.map(coin => tx.object(coin)));
        }
      }
      
      // Split exact amount for betting
      const [splitCoin] = tx.splitCoins(betCoin, [tx.pure.u64(betAmount)]);
      
      // Join the game
      tx.moveCall({
        target: `${this.packageId}::coin_flip::join_game`,
        arguments: [
          tx.object(gameId),
          splitCoin,
          tx.object(this.gameConfigId),
          tx.object(randomId),
          tx.object(clockId),
        ],
      });
      
      return tx;
    } catch (error) {
      throw new Error(`Failed to create join game transaction: ${error}`);
    }
  }

  /**
   * Cancel a game (only creator can cancel)
   * @param gameId - ID of the game to cancel
   * @returns Transaction ready to be signed and executed
   */
  async cancelGame(gameId: string): Promise<Transaction> {
    try {
      const tx = new Transaction();
      
      // Get required objects
      const clockId = await this.getClockObject();
      
      // Cancel the game
      tx.moveCall({
        target: `${this.packageId}::coin_flip::cancel_game`,
        arguments: [
          tx.object(gameId),
          tx.object(clockId),
        ],
      });
      
      return tx;
    } catch (error) {
      throw new Error(`Failed to create cancel game transaction: ${error}`);
    }
  }

  // ========================================
  // ADMIN FUNCTIONS
  // ========================================

  /**
   * Set fee percentage (admin only)
   * @param adminCapId - ID of the AdminCap object
   * @param feePercentage - New fee percentage in basis points (250 = 2.5%)
   * @returns Transaction ready to be signed and executed
   */
  async setFeePercentage(
    adminCapId: string, 
    feePercentage: number
  ): Promise<Transaction> {
    try {
      const tx = new Transaction();
      
      tx.moveCall({
        target: `${this.packageId}::coin_flip::update_fee_percentage`,
        arguments: [
          tx.object(adminCapId),
          tx.object(this.gameConfigId),
          tx.pure.u64(feePercentage),
        ],
      });
      
      return tx;
    } catch (error) {
      throw new Error(`Failed to create set fee transaction: ${error}`);
    }
  }

  /**
   * Update bet limits (admin only)
   * @param adminCapId - ID of the AdminCap object
   * @param minBet - Minimum bet amount in MIST
   * @param maxBet - Maximum bet amount in MIST
   * @returns Transaction ready to be signed and executed
   */
  async updateBetLimits(
    adminCapId: string, 
    minBet: string, 
    maxBet: string
  ): Promise<Transaction> {
    try {
      const tx = new Transaction();
      
      tx.moveCall({
        target: `${this.packageId}::coin_flip::update_bet_limits`,
        arguments: [
          tx.object(adminCapId),
          tx.object(this.gameConfigId),
          tx.pure.u64(minBet),
          tx.pure.u64(maxBet),
        ],
      });
      
      return tx;
    } catch (error) {
      throw new Error(`Failed to create update limits transaction: ${error}`);
    }
  }

  /**
   * Pause/unpause contract (admin only)
   * @param adminCapId - ID of the AdminCap object
   * @param paused - true to pause, false to unpause
   * @returns Transaction ready to be signed and executed
   */
  async setPauseState(
    adminCapId: string, 
    paused: boolean
  ): Promise<Transaction> {
    try {
      const tx = new Transaction();
      
      tx.moveCall({
        target: `${this.packageId}::coin_flip::set_pause_state`,
        arguments: [
          tx.object(adminCapId),
          tx.object(this.gameConfigId),
          tx.pure.bool(paused),
        ],
      });
      
      return tx;
    } catch (error) {
      throw new Error(`Failed to create pause state transaction: ${error}`);
    }
  }

  /**
   * Withdraw accumulated fees (admin only)
   * @param adminCapId - ID of the AdminCap object
   * @returns Transaction ready to be signed and executed
   */
  async withdrawFees(adminCapId: string): Promise<Transaction> {
    try {
      const tx = new Transaction();
      
      tx.moveCall({
        target: `${this.packageId}::coin_flip::withdraw_fees`,
        arguments: [
          tx.object(adminCapId),
          tx.object(this.gameConfigId),
        ],
      });
      
      return tx;
    } catch (error) {
      throw new Error(`Failed to create withdraw fees transaction: ${error}`);
    }
  }

  // ========================================
  // QUERY FUNCTIONS
  // ========================================

  /**
   * Get all active games (efficiently using events)
   * Returns games that have been created but not yet joined or cancelled
   */
  async getActiveGames(limit: number = 100): Promise<GameInfo[]> {
    try {
      // Get all GameCreated events
      const createdEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCreated`
        },
        limit,
        order: 'descending'
      });

      // Get all GameJoined events (completed games)
      const joinedEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameJoined`
        },
        limit,
        order: 'descending'
      });

      // Get all GameCancelled events
      const cancelledEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCancelled`
        },
        limit,
        order: 'descending'
      });

      // Create sets of completed/cancelled game IDs for fast lookup
      const completedGameIds = new Set(
        joinedEvents.data.map(event => (event.parsedJson as any).game_id)
      );
      const cancelledGameIds = new Set(
        cancelledEvents.data.map(event => (event.parsedJson as any).game_id)
      );

      // Filter active games (created but not completed or cancelled)
      const activeGames: GameInfo[] = [];
      
      for (const event of createdEvents.data) {
        const data = event.parsedJson as any;
        const gameId = data.game_id;
        
        // Skip if game has been completed or cancelled
        if (completedGameIds.has(gameId) || cancelledGameIds.has(gameId)) {
          continue;
        }
        
        activeGames.push({
          id: gameId,
          creator: data.creator,
          betAmount: data.bet_amount,
          creatorChoice: data.creator_choice,
          isActive: true,
          createdAt: data.created_at,
        });
      }
      
      return activeGames;
    } catch (error) {
      console.error('Failed to get active games:', error);
      return [];
    }
  }

  /**
   * Get games created by a specific user (efficiently using events)
   * Returns all games where the user is the creator, with their current status
   */
  async getUserGames(userAddress: string, limit: number = 100): Promise<GameInfo[]> {
    try {
      // Get all GameCreated events
      const createdEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCreated`
        },
        limit,
        order: 'descending'
      });

      // Get all GameJoined events (completed games) 
      const joinedEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameJoined`
        },
        limit,
        order: 'descending'
      });

      // Get all GameCancelled events
      const cancelledEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCancelled`
        },
        limit,
        order: 'descending'
      });

      // Create maps for fast lookup of game status
      const completedGames = new Map(
        joinedEvents.data.map(event => {
          const data = event.parsedJson as any;
          return [data.game_id, data];
        })
      );
      const cancelledGames = new Map(
        cancelledEvents.data.map(event => {
          const data = event.parsedJson as any;
          return [data.game_id, data];
        })
      );

      // Filter games created by the user
      const userGames: GameInfo[] = [];
      
      for (const event of createdEvents.data) {
        const data = event.parsedJson as any;
        
        // Only include games created by this user
        if (data.creator !== userAddress) {
          continue;
        }
        
        const gameId = data.game_id;
        let isActive = true;
        
        // Check if game has been completed or cancelled
        if (completedGames.has(gameId) || cancelledGames.has(gameId)) {
          isActive = false;
        }
        
        userGames.push({
          id: gameId,
          creator: data.creator,
          betAmount: data.bet_amount,
          creatorChoice: data.creator_choice,
          isActive,
          createdAt: data.created_at,
        });
      }
      
      return userGames;
    } catch (error) {
      throw new Error(`Failed to get user games: ${error}`);
    }
  }

  /**
   * Get specific game details
   */
  async getGameDetails(gameId: string): Promise<GameInfo | null> {
    try {
      const response = await this.client.getObject({
        id: gameId,
        options: { showContent: true }
      });

      if (!response.data?.content || response.data.content.dataType !== 'moveObject') {
        return null;
      }

      const fields = (response.data.content as any).fields;
      
      return {
        id: gameId,
        creator: fields.creator,
        betAmount: fields.bet_amount,
        creatorChoice: fields.creator_choice.fields.is_heads,
        isActive: fields.is_active,
        createdAt: fields.created_at_ms,
      };
    } catch (error) {
      throw new Error(`Failed to get game details: ${error}`);
    }
  }

  /**
   * Get all games a user has participated in (created or joined)
   */
  async getUserParticipatedGames(userAddress: string, limit: number = 100): Promise<GameInfo[]> {
    try {
      // Get games the user created
      const createdGames = await this.getUserGames(userAddress, limit);
      
      // Get games the user joined by looking at GameJoined events
      const joinedEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameJoined`
        },
        limit,
        order: 'descending'
      });

      // Find games where this user was the joiner
      const joinedGameIds = new Set<string>();
      for (const event of joinedEvents.data) {
        const data = event.parsedJson as any;
        if (data.joiner === userAddress) {
          joinedGameIds.add(data.game_id);
        }
      }

      // Get details for joined games by finding their creation events
      const createdEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCreated`
        },
        limit,
        order: 'descending'
      });

      const joinedGames: GameInfo[] = [];
      for (const event of createdEvents.data) {
        const data = event.parsedJson as any;
        if (joinedGameIds.has(data.game_id)) {
          joinedGames.push({
            id: data.game_id,
            creator: data.creator,
            betAmount: data.bet_amount,
            creatorChoice: data.creator_choice,
            isActive: false, // These games are completed since user joined them
            createdAt: data.created_at,
          });
        }
      }

      // Combine and deduplicate (user might have both created and joined the same game)
      const allGames = [...createdGames, ...joinedGames];
      const uniqueGames = allGames.filter((game, index, self) => 
        index === self.findIndex(g => g.id === game.id)
      );

      return uniqueGames.sort((a, b) => 
        parseInt(b.createdAt) - parseInt(a.createdAt)
      );
    } catch (error) {
      throw new Error(`Failed to get user participated games: ${error}`);
    }
  }

  /**
   * Get recent game activity (all games created in last period)
   */
  async getRecentGameActivity(
    hoursBack: number = 24, 
    limit: number = 50
  ): Promise<GameInfo[]> {
    try {
      const cutoffTime = Date.now() - (hoursBack * 60 * 60 * 1000);
      
      const createdEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCreated`
        },
        limit,
        order: 'descending'
      });

      // Get completion status for recent games
      const joinedEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameJoined`
        },
        limit,
        order: 'descending'
      });

      const cancelledEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCancelled`
        },
        limit,
        order: 'descending'
      });

      const completedGameIds = new Set(
        joinedEvents.data.map(event => (event.parsedJson as any).game_id)
      );
      const cancelledGameIds = new Set(
        cancelledEvents.data.map(event => (event.parsedJson as any).game_id)
      );

      const recentGames: GameInfo[] = [];
      
      for (const event of createdEvents.data) {
        const data = event.parsedJson as any;
        const createdTime = parseInt(data.created_at);
        
        // Skip if older than cutoff
        if (createdTime < cutoffTime) {
          continue;
        }
        
        const gameId = data.game_id;
        let isActive = true;
        
        if (completedGameIds.has(gameId) || cancelledGameIds.has(gameId)) {
          isActive = false;
        }
        
        recentGames.push({
          id: gameId,
          creator: data.creator,
          betAmount: data.bet_amount,
          creatorChoice: data.creator_choice,
          isActive,
          createdAt: data.created_at,
        });
      }
      
      return recentGames;
    } catch (error) {
      throw new Error(`Failed to get recent game activity: ${error}`);
    }
  }

  /**
   * Get game statistics for a user
   */
  async getUserGameStats(userAddress: string): Promise<{
    gamesCreated: number;
    gamesJoined: number;
    gamesWon: number;
    gamesLost: number;
    totalWinnings: string;
    totalLosses: string;
  }> {
    try {
      // Get games created by user
      const createdEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameCreated`
        },
        limit: 200,
        order: 'descending'
      });

      const gamesCreated = createdEvents.data.filter(event => 
        (event.parsedJson as any).creator === userAddress
      ).length;

      // Get games where user participated
      const joinedEvents = await this.client.queryEvents({
        query: {
          MoveEventType: `${this.packageId}::coin_flip::GameJoined`
        },
        limit: 200,
        order: 'descending'
      });

      let gamesJoined = 0;
      let gamesWon = 0;
      let gamesLost = 0;
      let totalWinnings = BigInt(0);
      let totalLosses = BigInt(0);

      for (const event of joinedEvents.data) {
        const data = event.parsedJson as any;
        
        // Check if user was involved in this game (either as creator or joiner)
        const isCreator = data.winner === userAddress || data.loser === userAddress;
        const isJoiner = data.joiner === userAddress;
        
        if (isJoiner) {
          gamesJoined++;
        }
        
        if (isCreator || isJoiner) {
          if (data.winner === userAddress) {
            gamesWon++;
            totalWinnings += BigInt(data.winner_payout);
          } else if (data.loser === userAddress) {
            gamesLost++;
            // Calculate loss amount (bet amount)
            const betAmount = BigInt(data.total_pot) - BigInt(data.fee_collected);
            totalLosses += betAmount / BigInt(2); // Each player bet half the pot
          }
        }
      }

      return {
        gamesCreated,
        gamesJoined,
        gamesWon,
        gamesLost,
        totalWinnings: totalWinnings.toString(),
        totalLosses: totalLosses.toString(),
      };
    } catch (error) {
      throw new Error(`Failed to get user game stats: ${error}`);
    }
  }

  /**
   * Get user's SUI balance
   */
  async getUserBalance(userAddress: string): Promise<string> {
    try {
      const balance = await this.client.getBalance({
        owner: userAddress,
        coinType: '0x2::sui::SUI',
      });
      
      return balance.totalBalance;
    } catch (error) {
      throw new Error(`Failed to get user balance: ${error}`);
    }
  }

  // ========================================
  // UTILITY FUNCTIONS
  // ========================================

  /**
   * Convert MIST to SUI (divide by 10^9)
   */
  static mistToSui(mist: string): string {
    return (BigInt(mist) / BigInt(1_000_000_000)).toString();
  }

  /**
   * Convert SUI to MIST (multiply by 10^9)
   */
  static suiToMist(sui: string): string {
    return (BigInt(Math.floor(parseFloat(sui) * 1_000_000_000))).toString();
  }

  /**
   * Format address for display (show first 6 and last 4 characters)
   */
  static formatAddress(address: string): string {
    if (address.length < 10) return address;
    return `${address.slice(0, 6)}...${address.slice(-4)}`;
  }

  /**
   * Check if user owns AdminCap
   */
  async isAdmin(userAddress: string): Promise<string | null> {
    try {
      const objects = await this.client.getOwnedObjects({
        owner: userAddress,
        filter: {
          StructType: `${this.packageId}::coin_flip::AdminCap`
        },
        options: {
          showContent: true,
        }
      });

      return objects.data.length > 0 ? objects.data[0].data?.objectId || null : null;
    } catch (error) {
      return null;
    }
  }
}

// ========================================
// USAGE EXAMPLES
// ========================================

/* 
// Example usage in a NextJS component or API route:

import { CoinFlipSDK } from './sui-coin-flip-sdk';

// Initialize SDK (use your actual deployment values)
const PACKAGE_ID = '0x4bb85342890080a28c96a5fa6751110fdbe36c1dfe3f66f44dc497ffec60bd58';
const GAME_CONFIG_ID = '0x741f172d57cd0929fba3e7815dc90eff15657f415cb46ff9024d8a4c7fd6c7b0';

const sdk = new CoinFlipSDK('testnet', PACKAGE_ID, GAME_CONFIG_ID);

// Example 1: Create a game
async function createGame(userAddress: string) {
  try {
    const betAmount = CoinFlipSDK.suiToMist('0.1'); // Bet 0.1 SUI
    const choice = true; // Choose heads
    
    const tx = await sdk.createGame(userAddress, betAmount, choice);
    
    // Sign and execute with wallet
    // const result = await wallet.signAndExecuteTransaction({ transaction: tx });
    console.log('Game created:', tx);
  } catch (error) {
    console.error('Failed to create game:', error);
  }
}

// Example 2: Join a game
async function joinGame(userAddress: string, gameId: string) {
  try {
    // First get game details to know the bet amount
    const gameDetails = await sdk.getGameDetails(gameId);
    if (!gameDetails) throw new Error('Game not found');
    
    const tx = await sdk.joinGame(userAddress, gameId, gameDetails.betAmount);
    
    // Sign and execute with wallet
    console.log('Joining game:', tx);
  } catch (error) {
    console.error('Failed to join game:', error);
  }
}

// Example 3: Get user's games and stats
async function getUserData(userAddress: string) {
  try {
    // Get active games for lobby
    const activeGames = await sdk.getActiveGames(50);
    console.log('Active games to join:', activeGames);
    
    // Get user's created games
    const userGames = await sdk.getUserGames(userAddress, 50);
    console.log('User created games:', userGames);
    
    // Get all games user participated in
    const participatedGames = await sdk.getUserParticipatedGames(userAddress, 100);
    console.log('User participated games:', participatedGames);
    
    // Get user statistics
    const stats = await sdk.getUserGameStats(userAddress);
    console.log('User stats:', {
      created: stats.gamesCreated,
      joined: stats.gamesJoined,
      won: stats.gamesWon,
      lost: stats.gamesLost,
      winnings: CoinFlipSDK.mistToSui(stats.totalWinnings) + ' SUI',
      losses: CoinFlipSDK.mistToSui(stats.totalLosses) + ' SUI'
    });
  } catch (error) {
    console.error('Failed to get user data:', error);
  }
}

// Example 4: Admin functions
async function adminSetFee(userAddress: string, newFeePercentage: number) {
  try {
    const adminCapId = await sdk.isAdmin(userAddress);
    if (!adminCapId) throw new Error('User is not admin');
    
    const tx = await sdk.setFeePercentage(adminCapId, newFeePercentage);
    console.log('Setting fee:', tx);
  } catch (error) {
    console.error('Failed to set fee:', error);
  }
}

// Example 5: Check contract status and recent activity
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
    
    // Get recent activity
    const recentGames = await sdk.getRecentGameActivity(24, 20); // Last 24 hours
    console.log('Recent activity:', recentGames.length + ' games in last 24h');
    
    // Filter active games by bet amount
    const activeGames = await sdk.getActiveGames(100);
    const highValueGames = activeGames.filter(game => 
      BigInt(game.betAmount) >= BigInt('500000000') // >= 0.5 SUI
    );
    const lowValueGames = activeGames.filter(game => 
      BigInt(game.betAmount) < BigInt('500000000') // < 0.5 SUI
    );
    
    console.log('Game distribution:', {
      total: activeGames.length,
      highValue: highValueGames.length,
      lowValue: lowValueGames.length
    });
  } catch (error) {
    console.error('Failed to check status:', error);
  }
}

*/

export default CoinFlipSDK; 