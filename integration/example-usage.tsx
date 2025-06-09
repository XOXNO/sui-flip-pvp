/**
 * Example React Component for SUI Coin Flip Game
 * This demonstrates how to use the CoinFlipSDK in a NextJS application
 * 
 * Make sure to install the required dapp kit:
 * npm install @mysten/dapp-kit @mysten/sui @tanstack/react-query
 */

import React, { useState, useEffect } from 'react';
import { useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit';
import { CoinFlipSDK, GameInfo, GameConfig } from './sui-coin-flip-sdk';

// Your deployed contract details - replace with actual values
const PACKAGE_ID = '0x4bb85342890080a28c96a5fa6751110fdbe36c1dfe3f66f44dc497ffec60bd58';
const GAME_CONFIG_ID = '0x741f172d57cd0929fba3e7815dc90eff15657f415cb46ff9024d8a4c7fd6c7b0';

const CoinFlipGame: React.FC = () => {
  const currentAccount = useCurrentAccount();
  const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction();
  
  // SDK instance
  const [sdk] = useState(() => new CoinFlipSDK('testnet', PACKAGE_ID, GAME_CONFIG_ID));
  
  // State
  const [userGames, setUserGames] = useState<GameInfo[]>([]);
  const [gameConfig, setGameConfig] = useState<GameConfig | null>(null);
  const [userBalance, setUserBalance] = useState<string>('0');
  const [loading, setLoading] = useState(false);
  const [isAdmin, setIsAdmin] = useState<string | null>(null);
  
  // Form states
  const [betAmount, setBetAmount] = useState('0.1');
  const [selectedChoice, setSelectedChoice] = useState<boolean>(true); // true = heads
  const [selectedGameId, setSelectedGameId] = useState<string>('');

  // Load data when wallet connects
  useEffect(() => {
    if (currentAccount?.address) {
      loadUserData();
    }
  }, [currentAccount?.address]);

  const loadUserData = async () => {
    if (!currentAccount?.address) return;
    
    setLoading(true);
    try {
      // Load all data in parallel
      const [games, config, balance, adminCap] = await Promise.all([
        sdk.getUserGames(currentAccount.address),
        sdk.getGameConfig(),
        sdk.getUserBalance(currentAccount.address),
        sdk.isAdmin(currentAccount.address)
      ]);
      
      setUserGames(games);
      setGameConfig(config);
      setUserBalance(balance);
      setIsAdmin(adminCap);
    } catch (error) {
      console.error('Failed to load user data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleCreateGame = async () => {
    if (!currentAccount?.address) return;
    
    setLoading(true);
    try {
      const betAmountMist = CoinFlipSDK.suiToMist(betAmount);
      const tx = await sdk.createGame(currentAccount.address, betAmountMist, selectedChoice);
      
      signAndExecuteTransaction(
        {
          transaction: tx,
        },
        {
          onSuccess: (result) => {
            console.log('Game created:', result);
            loadUserData();
            alert('Game created successfully!');
          },
          onError: (error) => {
            console.error('Failed to create game:', error);
            alert(`Failed to create game: ${error}`);
          },
        }
      );
    } catch (error) {
      console.error('Failed to create game:', error);
      alert(`Failed to create game: ${error}`);
    } finally {
      setLoading(false);
    }
  };

  const handleJoinGame = async (gameId: string) => {
    if (!currentAccount?.address) return;
    
    setLoading(true);
    try {
      // Get game details first
      const gameDetails = await sdk.getGameDetails(gameId);
      if (!gameDetails) {
        alert('Game not found');
        return;
      }
      
      const tx = await sdk.joinGame(currentAccount.address, gameId, gameDetails.betAmount);
      
      signAndExecuteTransaction(
        {
          transaction: tx,
        },
        {
          onSuccess: (result) => {
            console.log('Joined game:', result);
            loadUserData();
            alert('Game joined successfully!');
          },
          onError: (error) => {
            console.error('Failed to join game:', error);
            alert(`Failed to join game: ${error}`);
          },
        }
      );
    } catch (error) {
      console.error('Failed to join game:', error);
      alert(`Failed to join game: ${error}`);
    } finally {
      setLoading(false);
    }
  };

  const handleCancelGame = async (gameId: string) => {
    if (!currentAccount?.address) return;
    
    setLoading(true);
    try {
      const tx = await sdk.cancelGame(gameId);
      
      signAndExecuteTransaction(
        {
          transaction: tx,
        },
        {
          onSuccess: (result) => {
            console.log('Game cancelled:', result);
            loadUserData();
            alert('Game cancelled successfully!');
          },
          onError: (error) => {
            console.error('Failed to cancel game:', error);
            alert(`Failed to cancel game: ${error}`);
          },
        }
      );
    } catch (error) {
      console.error('Failed to cancel game:', error);
      alert(`Failed to cancel game: ${error}`);
    } finally {
      setLoading(false);
    }
  };

  const handleWithdrawFees = async () => {
    if (!currentAccount?.address || !isAdmin) return;
    
    setLoading(true);
    try {
      const tx = await sdk.withdrawFees(isAdmin);
      
      signAndExecuteTransaction(
        {
          transaction: tx,
        },
        {
          onSuccess: (result) => {
            console.log('Fees withdrawn:', result);
            loadUserData();
            alert('Fees withdrawn successfully!');
          },
          onError: (error) => {
            console.error('Failed to withdraw fees:', error);
            alert(`Failed to withdraw fees: ${error}`);
          },
        }
      );
    } catch (error) {
      console.error('Failed to withdraw fees:', error);
      alert(`Failed to withdraw fees: ${error}`);
    } finally {
      setLoading(false);
    }
  };

  if (!currentAccount) {
    return (
      <div className="p-6 bg-white rounded-lg shadow-lg">
        <h2 className="text-2xl font-bold mb-4">SUI Coin Flip Game</h2>
        <p className="text-gray-600">Please connect your wallet to play</p>
      </div>
    );
  }

  return (
    <div className="p-6 bg-white rounded-lg shadow-lg max-w-4xl mx-auto">
      <h2 className="text-3xl font-bold mb-6 text-center">SUI Coin Flip Game</h2>
      
      {/* User Info */}
      <div className="mb-6 p-4 bg-gray-50 rounded-lg">
        <h3 className="text-lg font-semibold mb-2">Your Info</h3>
        <p><strong>Address:</strong> {CoinFlipSDK.formatAddress(currentAccount.address)}</p>
        <p><strong>Balance:</strong> {CoinFlipSDK.mistToSui(userBalance)} SUI</p>
        {isAdmin && <p className="text-green-600"><strong>Admin Access:</strong> Yes</p>}
      </div>

      {/* Game Config */}
      {gameConfig && (
        <div className="mb-6 p-4 bg-blue-50 rounded-lg">
          <h3 className="text-lg font-semibold mb-2">Game Config</h3>
          <div className="grid grid-cols-2 gap-4">
            <p><strong>Fee:</strong> {gameConfig.feePercentage / 100}%</p>
            <p><strong>Status:</strong> {gameConfig.isPaused ? 'Paused' : 'Active'}</p>
            <p><strong>Min Bet:</strong> {CoinFlipSDK.mistToSui(gameConfig.minBetAmount)} SUI</p>
            <p><strong>Max Bet:</strong> {CoinFlipSDK.mistToSui(gameConfig.maxBetAmount)} SUI</p>
          </div>
          <p><strong>Treasury:</strong> {CoinFlipSDK.mistToSui(gameConfig.treasuryBalance)} SUI</p>
        </div>
      )}

      {/* Create Game */}
      <div className="mb-6 p-4 border rounded-lg">
        <h3 className="text-lg font-semibold mb-4">Create New Game</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
          <div>
            <label className="block text-sm font-medium mb-2">Bet Amount (SUI)</label>
            <input
              type="number"
              step="0.01"
              value={betAmount}
              onChange={(e) => setBetAmount(e.target.value)}
              className="w-full px-3 py-2 border rounded-md"
              placeholder="0.1"
            />
          </div>
          <div>
            <label className="block text-sm font-medium mb-2">Your Choice</label>
            <select
              value={selectedChoice.toString()}
              onChange={(e) => setSelectedChoice(e.target.value === 'true')}
              className="w-full px-3 py-2 border rounded-md"
            >
              <option value="true">Heads</option>
              <option value="false">Tails</option>
            </select>
          </div>
          <div className="flex items-end">
            <button
              onClick={handleCreateGame}
              disabled={loading || !betAmount}
              className="w-full px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:bg-gray-400"
            >
              {loading ? 'Creating...' : 'Create Game'}
            </button>
          </div>
        </div>
      </div>

      {/* Join Game */}
      <div className="mb-6 p-4 border rounded-lg">
        <h3 className="text-lg font-semibold mb-4">Join Existing Game</h3>
        <div className="flex gap-4">
          <input
            type="text"
            value={selectedGameId}
            onChange={(e) => setSelectedGameId(e.target.value)}
            className="flex-1 px-3 py-2 border rounded-md"
            placeholder="Game ID"
          />
          <button
            onClick={() => handleJoinGame(selectedGameId)}
            disabled={loading || !selectedGameId}
            className="px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 disabled:bg-gray-400"
          >
            {loading ? 'Joining...' : 'Join Game'}
          </button>
        </div>
      </div>

      {/* User Games */}
      <div className="mb-6">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-semibold">Your Games</h3>
          <button
            onClick={loadUserData}
            disabled={loading}
            className="px-4 py-2 bg-gray-600 text-white rounded-md hover:bg-gray-700 disabled:bg-gray-400"
          >
            {loading ? 'Loading...' : 'Refresh'}
          </button>
        </div>
        
        {userGames.length === 0 ? (
          <p className="text-gray-600">No games found</p>
        ) : (
          <div className="space-y-4">
            {userGames.map((game) => (
              <div key={game.id} className="p-4 border rounded-lg">
                <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
                  <div>
                    <p className="text-sm font-medium">Game ID</p>
                    <p className="text-xs text-gray-600">{CoinFlipSDK.formatAddress(game.id)}</p>
                  </div>
                  <div>
                    <p className="text-sm font-medium">Bet Amount</p>
                    <p>{CoinFlipSDK.mistToSui(game.betAmount)} SUI</p>
                  </div>
                  <div>
                    <p className="text-sm font-medium">Your Choice</p>
                    <p>{game.creatorChoice ? 'Heads' : 'Tails'}</p>
                  </div>
                  <div>
                    <p className="text-sm font-medium">Status</p>
                    <div className="flex gap-2">
                      <span className={`px-2 py-1 text-xs rounded ${
                        game.isActive ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'
                      }`}>
                        {game.isActive ? 'Active' : 'Finished'}
                      </span>
                      {game.isActive && game.creator === currentAccount?.address && (
                        <button
                          onClick={() => handleCancelGame(game.id)}
                          disabled={loading}
                          className="px-2 py-1 text-xs bg-red-600 text-white rounded hover:bg-red-700 disabled:bg-gray-400"
                        >
                          Cancel
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Admin Panel */}
      {isAdmin && (
        <div className="p-4 border-2 border-yellow-400 rounded-lg bg-yellow-50">
          <h3 className="text-lg font-semibold mb-4 text-yellow-800">Admin Panel</h3>
          <button
            onClick={handleWithdrawFees}
            disabled={loading}
            className="px-4 py-2 bg-yellow-600 text-white rounded-md hover:bg-yellow-700 disabled:bg-gray-400"
          >
            {loading ? 'Processing...' : 'Withdraw Fees'}
          </button>
        </div>
      )}
    </div>
  );
};

export default CoinFlipGame; 