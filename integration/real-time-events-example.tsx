/**
 * Real-time Coin Flip Events Example Component
 * Demonstrates how to use the events hook with animations and notifications
 */

import React, { useState } from 'react';
import { useCoinFlipEvents } from './useCoinFlipEvents';
import { GameCreatedEvent, GameJoinedEvent, GameCancelledEvent } from './sui-events-listener';
import { CoinFlipSDK } from './sui-coin-flip-sdk';

// Your contract details
const PACKAGE_ID = '0x4bb85342890080a28c96a5fa6751110fdbe36c1dfe3f66f44dc497ffec60bd58';
const NETWORK = 'testnet';

// Notification component with animations
const EventNotification: React.FC<{
  event: any;
  type: 'created' | 'joined' | 'cancelled';
  onClose: () => void;
}> = ({ event, type, onClose }) => {
  const getEventMessage = () => {
    switch (type) {
      case 'created':
        const created = event as GameCreatedEvent;
        return `🎮 New game created! Bet: ${CoinFlipSDK.mistToSui(created.bet_amount)} SUI`;
      case 'joined':
        const joined = event as GameJoinedEvent;
        return `🎯 Game completed! Winner: ${CoinFlipSDK.formatAddress(joined.winner)}`;
      case 'cancelled':
        const cancelled = event as GameCancelledEvent;
        return `❌ Game cancelled. Refund: ${CoinFlipSDK.mistToSui(cancelled.refund_amount)} SUI`;
    }
  };

  const getColorClass = () => {
    switch (type) {
      case 'created': return 'bg-blue-500';
      case 'joined': return 'bg-green-500';
      case 'cancelled': return 'bg-red-500';
    }
  };

  return (
    <div className={`fixed top-4 right-4 ${getColorClass()} text-white px-6 py-4 rounded-lg shadow-lg z-50 animate-slide-in-right max-w-sm`}>
      <div className="flex justify-between items-start">
        <div className="pr-4">
          <p className="text-sm font-medium">{getEventMessage()}</p>
          <p className="text-xs opacity-90 mt-1">
            {type === 'created' && `Choice: ${(event as GameCreatedEvent).creator_choice ? 'Heads' : 'Tails'}`}
            {type === 'joined' && `Result: ${(event as GameJoinedEvent).coin_flip_result ? 'Heads' : 'Tails'}`}
          </p>
        </div>
        <button 
          onClick={onClose}
          className="text-white hover:text-gray-200 text-lg leading-none"
        >
          ×
        </button>
      </div>
    </div>
  );
};

// Main component
export const RealTimeEventsExample: React.FC = () => {
  const [notifications, setNotifications] = useState<Array<{
    id: string;
    event: any;
    type: 'created' | 'joined' | 'cancelled';
  }>>([]);

  // Use the events hook
  const {
    isConnected,
    error,
    recentEvents,
    gameCreatedEvents,
    gameJoinedEvents,
    gameCancelledEvents,
    connect,
    disconnect,
    clearEvents
  } = useCoinFlipEvents({
    packageId: PACKAGE_ID,
    network: NETWORK,
    autoConnect: true,
    maxRecentEvents: 20,
    onGameCreated: (event) => {
      console.log('🎮 NEW GAME CREATED:', event);
      // Add notification
      addNotification(event, 'created');
      // Trigger animation or sound here
      playNotificationSound('game-created');
    },
    onGameJoined: (event) => {
      console.log('🎯 GAME COMPLETED:', event);
      addNotification(event, 'joined');
      playNotificationSound('game-completed');
      // You could trigger confetti animation here for the winner
    },
    onGameCancelled: (event) => {
      console.log('❌ GAME CANCELLED:', event);
      addNotification(event, 'cancelled');
      playNotificationSound('game-cancelled');
    }
  });

  // Add notification with auto-remove after 5 seconds
  const addNotification = (event: any, type: 'created' | 'joined' | 'cancelled') => {
    const id = Date.now().toString();
    setNotifications(prev => [...prev, { id, event, type }]);
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      removeNotification(id);
    }, 5000);
  };

  const removeNotification = (id: string) => {
    setNotifications(prev => prev.filter(n => n.id !== id));
  };

  // Play notification sounds (you would implement actual sound logic)
  const playNotificationSound = (soundType: string) => {
    // Example: new Audio(`/sounds/${soundType}.mp3`).play();
    console.log(`🔊 Playing sound: ${soundType}`);
  };

  return (
    <div className="p-6 max-w-6xl mx-auto">
      {/* Connection Status */}
      <div className="mb-6 p-4 rounded-lg bg-gray-50">
        <h2 className="text-xl font-bold mb-2">Real-Time Events Monitor</h2>
        <div className="flex items-center space-x-4">
          <div className={`flex items-center space-x-2 ${isConnected ? 'text-green-600' : 'text-red-600'}`}>
            <div className={`w-3 h-3 rounded-full ${isConnected ? 'bg-green-500 animate-pulse' : 'bg-red-500'}`}></div>
            <span className="font-medium">
              {isConnected ? 'Connected' : 'Disconnected'}
            </span>
          </div>
          
          <button
            onClick={isConnected ? disconnect : connect}
            className={`px-4 py-2 rounded-md text-white font-medium ${
              isConnected ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'
            }`}
          >
            {isConnected ? 'Disconnect' : 'Connect'}
          </button>
          
          <button
            onClick={clearEvents}
            className="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700"
          >
            Clear Events
          </button>
        </div>
        
        {error && (
          <div className="mt-2 p-2 bg-red-100 text-red-700 rounded">
            Error: {error.message}
          </div>
        )}
      </div>

      {/* Event Statistics */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <div className="bg-blue-50 p-4 rounded-lg">
          <h3 className="font-semibold text-blue-800">Games Created</h3>
          <p className="text-2xl font-bold text-blue-600">{gameCreatedEvents.length}</p>
        </div>
        <div className="bg-green-50 p-4 rounded-lg">
          <h3 className="font-semibold text-green-800">Games Completed</h3>
          <p className="text-2xl font-bold text-green-600">{gameJoinedEvents.length}</p>
        </div>
        <div className="bg-red-50 p-4 rounded-lg">
          <h3 className="font-semibold text-red-800">Games Cancelled</h3>
          <p className="text-2xl font-bold text-red-600">{gameCancelledEvents.length}</p>
        </div>
        <div className="bg-purple-50 p-4 rounded-lg">
          <h3 className="font-semibold text-purple-800">Total Events</h3>
          <p className="text-2xl font-bold text-purple-600">{recentEvents.length}</p>
        </div>
      </div>

      {/* Recent Events Feed */}
      <div className="bg-white border rounded-lg shadow">
        <div className="p-4 border-b">
          <h3 className="text-lg font-semibold">Live Events Feed</h3>
        </div>
        <div className="max-h-96 overflow-y-auto">
          {recentEvents.length === 0 ? (
            <div className="p-8 text-center text-gray-500">
              <p>No events yet. Waiting for real-time updates...</p>
              <div className="mt-2 flex justify-center">
                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-500"></div>
              </div>
            </div>
          ) : (
            <div className="divide-y">
              {recentEvents.map((event, index) => (
                <div key={index} className="p-4 hover:bg-gray-50 transition-colors">
                  <div className="flex items-start justify-between">
                    <div className="flex-1">
                      <div className="flex items-center space-x-2">
                        <span className={`px-2 py-1 text-xs rounded font-medium ${
                          event.type === 'GameCreated' ? 'bg-blue-100 text-blue-800' :
                          event.type === 'GameJoined' ? 'bg-green-100 text-green-800' :
                          'bg-red-100 text-red-800'
                        }`}>
                          {event.type}
                        </span>
                        <span className="text-sm text-gray-500">
                          {new Date(event.timestamp).toLocaleTimeString()}
                        </span>
                      </div>
                      
                      <div className="mt-2">
                        {event.type === 'GameCreated' && (
                          <div className="text-sm">
                            <p className="font-medium">Game ID: {CoinFlipSDK.formatAddress(event.data.game_id)}</p>
                            <p>Creator: {CoinFlipSDK.formatAddress((event.data as GameCreatedEvent).creator)}</p>
                            <p>Bet: {CoinFlipSDK.mistToSui((event.data as GameCreatedEvent).bet_amount)} SUI</p>
                            <p>Choice: {(event.data as GameCreatedEvent).creator_choice ? 'Heads' : 'Tails'}</p>
                          </div>
                        )}
                        
                        {event.type === 'GameJoined' && (
                          <div className="text-sm">
                            <p className="font-medium">Game ID: {CoinFlipSDK.formatAddress(event.data.game_id)}</p>
                            <p>Winner: {CoinFlipSDK.formatAddress((event.data as GameJoinedEvent).winner)} 🏆</p>
                            <p>Payout: {CoinFlipSDK.mistToSui((event.data as GameJoinedEvent).winner_payout)} SUI</p>
                            <p>Result: {(event.data as GameJoinedEvent).coin_flip_result ? 'Heads' : 'Tails'}</p>
                          </div>
                        )}
                        
                        {event.type === 'GameCancelled' && (
                          <div className="text-sm">
                            <p className="font-medium">Game ID: {CoinFlipSDK.formatAddress(event.data.game_id)}</p>
                            <p>Creator: {CoinFlipSDK.formatAddress((event.data as GameCancelledEvent).creator)}</p>
                            <p>Refund: {CoinFlipSDK.mistToSui((event.data as GameCancelledEvent).refund_amount)} SUI</p>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Toast Notifications */}
      {notifications.map(notification => (
        <EventNotification
          key={notification.id}
          event={notification.event}
          type={notification.type}
          onClose={() => removeNotification(notification.id)}
        />
      ))}
      
      {/* CSS for animations */}
      <style>
        {`
          @keyframes slide-in-right {
            from {
              transform: translateX(100%);
              opacity: 0;
            }
            to {
              transform: translateX(0);
              opacity: 1;
            }
          }
          
          .animate-slide-in-right {
            animation: slide-in-right 0.3s ease-out;
          }
        `}
      </style>
    </div>
  );
};

export default RealTimeEventsExample; 