/**
 * React Hook for SUI Coin Flip Events
 * Easy integration of real-time events into React components
 */

import { useState, useEffect, useRef, useCallback } from 'react';
import { 
  CoinFlipEventsListener, 
  EventListenerOptions,
  GameCreatedEvent,
  GameJoinedEvent,
  GameCancelledEvent,
  ParsedCoinFlipEvent
} from './sui-events-listener';

interface CoinFlipEventsState {
  isConnected: boolean;
  error: Error | null;
  recentEvents: ParsedCoinFlipEvent[];
  gameCreatedEvents: GameCreatedEvent[];
  gameJoinedEvents: GameJoinedEvent[];
  gameCancelledEvents: GameCancelledEvent[];
}

interface UseCoinFlipEventsOptions {
  packageId: string;
  network: 'mainnet' | 'testnet' | 'devnet' | 'localnet';
  autoConnect?: boolean;
  maxRecentEvents?: number;
  onGameCreated?: (event: GameCreatedEvent) => void;
  onGameJoined?: (event: GameJoinedEvent) => void;
  onGameCancelled?: (event: GameCancelledEvent) => void;
}

export function useCoinFlipEvents(options: UseCoinFlipEventsOptions) {
  const {
    packageId,
    network,
    autoConnect = true,
    maxRecentEvents = 50,
    onGameCreated,
    onGameJoined,
    onGameCancelled
  } = options;

  const [state, setState] = useState<CoinFlipEventsState>({
    isConnected: false,
    error: null,
    recentEvents: [],
    gameCreatedEvents: [],
    gameJoinedEvents: [],
    gameCancelledEvents: []
  });

  const listenerRef = useRef<CoinFlipEventsListener | null>(null);

  // Helper function to add event to recent events with limit
  const addToRecentEvents = useCallback((newEvent: ParsedCoinFlipEvent) => {
    setState(prev => ({
      ...prev,
      recentEvents: [newEvent, ...prev.recentEvents].slice(0, maxRecentEvents)
    }));
  }, [maxRecentEvents]);

  // Handle game created events
  const handleGameCreated = useCallback((event: GameCreatedEvent, rawEvent: any) => {
    const parsedEvent: ParsedCoinFlipEvent = {
      type: 'GameCreated',
      data: event,
      rawEvent,
      timestamp: Date.now()
    };

    setState(prev => ({
      ...prev,
      gameCreatedEvents: [event, ...prev.gameCreatedEvents]
    }));

    addToRecentEvents(parsedEvent);
    onGameCreated?.(event);
  }, [onGameCreated, addToRecentEvents]);

  // Handle game joined events
  const handleGameJoined = useCallback((event: GameJoinedEvent, rawEvent: any) => {
    const parsedEvent: ParsedCoinFlipEvent = {
      type: 'GameJoined',
      data: event,
      rawEvent,
      timestamp: Date.now()
    };

    setState(prev => ({
      ...prev,
      gameJoinedEvents: [event, ...prev.gameJoinedEvents]
    }));

    addToRecentEvents(parsedEvent);
    onGameJoined?.(event);
  }, [onGameJoined, addToRecentEvents]);

  // Handle game cancelled events
  const handleGameCancelled = useCallback((event: GameCancelledEvent, rawEvent: any) => {
    const parsedEvent: ParsedCoinFlipEvent = {
      type: 'GameCancelled',
      data: event,
      rawEvent,
      timestamp: Date.now()
    };

    setState(prev => ({
      ...prev,
      gameCancelledEvents: [event, ...prev.gameCancelledEvents]
    }));

    addToRecentEvents(parsedEvent);
    onGameCancelled?.(event);
  }, [onGameCancelled, addToRecentEvents]);

  // Handle connection events
  const handleConnect = useCallback(() => {
    setState(prev => ({ ...prev, isConnected: true, error: null }));
  }, []);

  const handleDisconnect = useCallback(() => {
    setState(prev => ({ ...prev, isConnected: false }));
  }, []);

  const handleError = useCallback((error: Error) => {
    setState(prev => ({ ...prev, error, isConnected: false }));
  }, []);

  // Connect to events
  const connect = useCallback(async () => {
    if (listenerRef.current?.getConnectionStatus()) {
      return; // Already connected
    }

    try {
      const listener = new CoinFlipEventsListener({
        packageId,
        network,
        onGameCreated: handleGameCreated,
        onGameJoined: handleGameJoined,
        onGameCancelled: handleGameCancelled,
        onConnect: handleConnect,
        onDisconnect: handleDisconnect,
        onError: handleError
      });

      listenerRef.current = listener;
      await listener.startListening();
    } catch (error) {
      handleError(error as Error);
    }
  }, [
    packageId,
    network,
    handleGameCreated,
    handleGameJoined,
    handleGameCancelled,
    handleConnect,
    handleDisconnect,
    handleError
  ]);

  // Disconnect from events
  const disconnect = useCallback(async () => {
    if (listenerRef.current) {
      await listenerRef.current.stopListening();
      listenerRef.current = null;
    }
  }, []);

  // Get historical events
  const getHistoricalEvents = useCallback(async (eventType: 'GameCreated' | 'GameJoined' | 'GameCancelled', limit?: number) => {
    if (!listenerRef.current) return [];
    return await listenerRef.current.getHistoricalEvents(eventType, limit);
  }, []);

  // Get events for specific game
  const getGameEvents = useCallback(async (gameId: string) => {
    if (!listenerRef.current) return [];
    return await listenerRef.current.getGameEvents(gameId);
  }, []);

  // Auto-connect on mount if enabled
  useEffect(() => {
    if (autoConnect) {
      connect();
    }

    // Cleanup on unmount
    return () => {
      disconnect();
    };
  }, [autoConnect, connect, disconnect]);

  return {
    // Connection state
    isConnected: state.isConnected,
    error: state.error,
    
    // Event data
    recentEvents: state.recentEvents,
    gameCreatedEvents: state.gameCreatedEvents,
    gameJoinedEvents: state.gameJoinedEvents,
    gameCancelledEvents: state.gameCancelledEvents,
    
    // Actions
    connect,
    disconnect,
    getHistoricalEvents,
    getGameEvents,
    
    // Clear events
    clearEvents: () => setState(prev => ({
      ...prev,
      recentEvents: [],
      gameCreatedEvents: [],
      gameJoinedEvents: [],
      gameCancelledEvents: []
    }))
  };
} 