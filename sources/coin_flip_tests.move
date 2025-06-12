#[test_only]
module sui_coin_flip::coin_flip_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::random;
    use sui::clock::{Self};
    use sui_coin_flip::coin_flip::{
        Self, 
        Game, 
        GameConfig, 
        AdminCap,
    };

    // Test addresses
    const ADMIN: address = @0xAD;
    const PLAYER1: address = @0xA1;
    const PLAYER2: address = @0xA2;
    const SYSTEM: address = @0x0;
    
    // Test amounts in mist (1 SUI = 1,000,000,000 mist)
    const TEST_BET_AMOUNT: u64 = 200_000_000; // 0.2 SUI

    #[test]
    fun test_init() {
        let mut scenario = test::begin(ADMIN);
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };
        
        next_tx(&mut scenario, ADMIN);
        {
            // Admin should receive AdminCap
            assert!(test::has_most_recent_for_sender<AdminCap>(&scenario), 0);
            
            // GameConfig should be shared
            assert!(test::has_most_recent_shared<GameConfig>(), 1);
        };
        
        test::end(scenario);
    }

    #[test]
    fun test_create_game() {
        let mut scenario = test::begin(PLAYER1);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario)); // bet on heads
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        next_tx(&mut scenario, PLAYER1);
        {
            // Game should be created and shared
            assert!(test::has_most_recent_shared<Game<SUI>>(), 0);
        };

        test::end(scenario);
    }

    #[test]
    fun test_cancel_game() {
        let mut scenario = test::begin(PLAYER1);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates a game
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Player 1 cancels the game
        next_tx(&mut scenario, PLAYER1);
        {
            let game = test::take_shared<Game<SUI>>(&scenario);
            coin_flip::cancel_game(game, ctx(&mut scenario));
        };

        // Player 1 should receive refund
        next_tx(&mut scenario, PLAYER1);
        {
            assert!(test::has_most_recent_for_sender<Coin<SUI>>(&scenario), 0);
            let refund_coin = test::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&refund_coin) == 200_000_000, 1);
            test::return_to_sender(&scenario, refund_coin);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ENotGameCreator)]
    fun test_non_creator_cannot_cancel() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates a game
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Player 2 tries to cancel Player 1's game (should fail)
        next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game<SUI>>(&scenario);
            coin_flip::cancel_game(game, ctx(&mut scenario));
        };

        test::end(scenario);
    }

    #[test]
    fun test_update_fee_percentage() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Update fee percentage to 5%
            coin_flip::update_fee_percentage(&admin_cap, &mut config, 500, ctx(&mut scenario));
            
            // Check updated fee percentage
            assert!(coin_flip::get_fee_percentage(&config) == 500, 0);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidAdminCap)]
    fun test_invalid_admin_cap() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            // Create a fake admin cap
            let fake_admin_cap = coin_flip::create_admin_cap_for_testing(ctx(&mut scenario));
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to update fee with fake admin cap (should fail)
            coin_flip::update_fee_percentage(&fake_admin_cap, &mut config, 500, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, fake_admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_treasury_address_functions() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Check initial treasury address
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            
            // Treasury address should be set to deployer (ADMIN)
            let treasury_address = coin_flip::get_treasury_address(&config);
            assert!(treasury_address == ADMIN, 0);
            
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_update_treasury_address() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Update treasury address
            coin_flip::update_treasury_address(&admin_cap, &mut config, PLAYER1, ctx(&mut scenario));
            
            // Check updated treasury address
            assert!(coin_flip::get_treasury_address(&config) == PLAYER1, 0);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_game_info_view() {
        let mut scenario = test::begin(PLAYER1);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates a game
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario)); // bet on heads
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        next_tx(&mut scenario, PLAYER1);
        {
            let game = test::take_shared<Game<SUI>>(&scenario);
            let (creator, bet_amount, creator_choice_heads, is_active, _created_at) = coin_flip::get_game_info(&game);
            
            assert!(creator == PLAYER1, 0);
            assert!(bet_amount == 200_000_000, 1);
            assert!(creator_choice_heads == true, 2);
            assert!(is_active == true, 3);
            
            test::return_shared(game);
        };

        test::end(scenario);
    }

    #[test]
    fun test_config_view_functions() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            
            // Test view functions
            let fee_percentage = coin_flip::get_fee_percentage(&config);
            let treasury_address = coin_flip::get_treasury_address(&config);
            
            assert!(fee_percentage == 250, 0); // Default 2.5%
            assert!(treasury_address == ADMIN, 1); // Initially set to deployer
            
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidFeePercentage)]
    fun test_invalid_fee_percentage() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to set fee percentage > 100% (should fail)
            coin_flip::update_fee_percentage(&admin_cap, &mut config, 20000, ctx(&mut scenario)); // 200%
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidBetAmount)]
    fun test_invalid_bet_amount_zero() {
        let mut scenario = test::begin(PLAYER1);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            // Try to create a game with 0 SUI bet (should fail)
            let bet_coin = coin::mint_for_testing<SUI>(0, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        test::end(scenario);
    }

    #[test]
    fun test_inactive_game_state() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates a game
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Set the game as inactive using test helper
        next_tx(&mut scenario, ADMIN);
        {
            let mut game = test::take_shared<Game<SUI>>(&scenario);
            coin_flip::set_game_inactive_for_testing(&mut game);
            test::return_shared(game);
        };

        // Verify the game is now inactive
        next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game<SUI>>(&scenario);
            let (_, _, _, is_active, _) = coin_flip::get_game_info(&game);
            
            // Verify game is inactive - in real usage, calling join_game 
            // on this inactive game would trigger EGameNotFound
            assert!(!is_active, 0);
            
            test::return_shared(game);
        };

        test::end(scenario);
    }

    #[test]
    fun test_bulk_join_games() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates two games
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create first game
            let bet_coin1 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin1, true, &config, &clock, ctx(&mut scenario));
            
            // Create second game
            let bet_coin2 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin2, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Update randomness state (must be done by system)
        next_tx(&mut scenario, SYSTEM);
        {
            let mut rnd = test::take_shared<random::Random>(&scenario);
            
            random::update_randomness_state_for_testing(
                &mut rnd, 
                0, 
                x"0000000000000000000000000000000000000000000000000000000000000000", 
                ctx(&mut scenario)
            );
            
            test::return_shared(rnd);
        };

        // Player 2 joins both games using bulk function
        next_tx(&mut scenario, PLAYER2);
        {
            let game1 = test::take_shared<Game<SUI>>(&scenario);
            let game2 = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector of games
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game1);
            vector::push_back(&mut games, game2);
            
            // Create payment for both games (2 * TEST_BET_AMOUNT)
            let total_payment = coin::mint_for_testing<SUI>(2 * TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Join both games in bulk
            coin_flip::join_games(games, total_payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        // Check that someone received winnings from both games
        next_tx(&mut scenario, PLAYER1);
        {
            // Player1 might have won one or both games
            while (test::has_most_recent_for_sender<Coin<SUI>>(&scenario)) {
                let payout_coin = test::take_from_sender<Coin<SUI>>(&scenario);
                // Each game payout should be 390M (400M total pot - 10M fee)
                assert!(coin::value(&payout_coin) == 390_000_000, 1);
                test::return_to_sender(&scenario, payout_coin);
            };
        };

        next_tx(&mut scenario, PLAYER2);
        {
            // Player2 might have won one or both games
            while (test::has_most_recent_for_sender<Coin<SUI>>(&scenario)) {
                let payout_coin = test::take_from_sender<Coin<SUI>>(&scenario);
                // Each game payout should be 390M (400M total pot - 10M fee)
                assert!(coin::value(&payout_coin) == 390_000_000, 2);
                test::return_to_sender(&scenario, payout_coin);
            };
        };

        // Check that treasury address received fees (fees are sent directly to treasury address)
        next_tx(&mut scenario, ADMIN);
        {
            // Admin (treasury address) should receive fee coins directly
            while (test::has_most_recent_for_sender<Coin<SUI>>(&scenario)) {
                let fee_coin = test::take_from_sender<Coin<SUI>>(&scenario);
                // Each game generates 10M fee (2.5% of 400M pot)
                assert!(coin::value(&fee_coin) == 10_000_000, 3);
                test::return_to_sender(&scenario, fee_coin);
            };
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInsufficientPayment)]
    fun test_bulk_join_games_insufficient_payment() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates two games
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create first game
            let bet_coin1 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin1, true, &config, &clock, ctx(&mut scenario));
            
            // Create second game
            let bet_coin2 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin2, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Player 2 tries to join both games with insufficient payment (should fail)
        next_tx(&mut scenario, PLAYER2);
        {
            let game1 = test::take_shared<Game<SUI>>(&scenario);
            let game2 = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector of games
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game1);
            vector::push_back(&mut games, game2);
            
            // Create insufficient payment (only enough for 1 game, not 2)
            let insufficient_payment = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Try to join both games with insufficient payment (should fail)
            coin_flip::join_games(games, insufficient_payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EGameNotFound)]
    fun test_bulk_join_games_empty_vector() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Player 2 tries to join empty games vector (should fail)
        next_tx(&mut scenario, PLAYER2);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create empty vector of games
            let empty_games = vector::empty<Game<SUI>>();
            
            // Create payment
            let payment = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Try to join empty games vector (should fail)
            coin_flip::join_games(empty_games, payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ECannotJoinOwnGame)]
    fun test_bulk_join_games_own_games() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates two games
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create first game
            let bet_coin1 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin1, true, &config, &clock, ctx(&mut scenario));
            
            // Create second game
            let bet_coin2 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin2, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Player 1 tries to join their own games (should fail)
        next_tx(&mut scenario, PLAYER1);
        {
            let game1 = test::take_shared<Game<SUI>>(&scenario);
            let game2 = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector of games
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game1);
            vector::push_back(&mut games, game2);
            
            // Create payment for both games
            let payment = coin::mint_for_testing<SUI>(2 * TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Try to join own games (should fail)
            coin_flip::join_games(games, payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EContractPaused)]
    fun test_bulk_join_games_when_paused() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates a game
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Admin pauses the contract
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::set_pause_state(&admin_cap, &mut config, true, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Player 2 tries to join games while contract is paused (should fail)
        next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector of games
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game);
            
            // Create payment
            let payment = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Try to join games while paused (should fail)
            coin_flip::join_games(games, payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    fun test_bulk_join_games_with_overpayment() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates two games
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create first game
            let bet_coin1 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin1, true, &config, &clock, ctx(&mut scenario));
            
            // Create second game
            let bet_coin2 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin2, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Update randomness state (must be done by system)
        next_tx(&mut scenario, SYSTEM);
        {
            let mut rnd = test::take_shared<random::Random>(&scenario);
            
            random::update_randomness_state_for_testing(
                &mut rnd, 
                0, 
                x"0000000000000000000000000000000000000000000000000000000000000000", 
                ctx(&mut scenario)
            );
            
            test::return_shared(rnd);
        };

        // Player 2 joins both games with overpayment
        next_tx(&mut scenario, PLAYER2);
        {
            let game1 = test::take_shared<Game<SUI>>(&scenario);
            let game2 = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector of games
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game1);
            vector::push_back(&mut games, game2);
            
            // Create overpayment (3x required amount instead of 2x)
            let overpayment = coin::mint_for_testing<SUI>(3 * TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Join both games with overpayment
            coin_flip::join_games(games, overpayment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        // Check that Player 2 received excess payment back
        next_tx(&mut scenario, PLAYER2);
        {
            // Player2 should have received excess payment back (1 * TEST_BET_AMOUNT)
            let mut refund_received = false;
            while (test::has_most_recent_for_sender<Coin<SUI>>(&scenario)) {
                let coin = test::take_from_sender<Coin<SUI>>(&scenario);
                let coin_value = coin::value(&coin);
                
                if (coin_value == TEST_BET_AMOUNT) {
                    // This is the excess refund
                    refund_received = true;
                    test::return_to_sender(&scenario, coin);
                } else {
                    // This is a game win payout
                    assert!(coin_value == 390_000_000, 1); // 400M total pot - 10M fee
                    test::return_to_sender(&scenario, coin);
                };
            };
            
            assert!(refund_received, 0); // Ensure we got the refund
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EGameNotFound)]
    fun test_bulk_join_games_inactive_games() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Player 1 creates a game
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Set the game as inactive using test helper
        next_tx(&mut scenario, ADMIN);
        {
            let mut game = test::take_shared<Game<SUI>>(&scenario);
            coin_flip::set_game_inactive_for_testing(&mut game);
            test::return_shared(game);
        };

        // Player 2 tries to join inactive game (should fail)
        next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector with inactive game
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game);
            
            // Create payment
            let payment = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Try to join inactive game (should fail)
            coin_flip::join_games(games, payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    // ======== Max Games Per Transaction Tests ========

    #[test]
    fun test_default_max_games_limit() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            
            // Check default max games limit (should be 100)
            let max_games = coin_flip::get_max_games_per_transaction(&config);
            assert!(max_games == 100, 0);
            
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_admin_update_max_games_limit() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Test default value
            assert!(coin_flip::get_max_games_per_transaction(&config) == 100, 0);
            
            // Update to 50
            coin_flip::update_max_games_per_transaction(&admin_cap, &mut config, 50, ctx(&mut scenario));
            assert!(coin_flip::get_max_games_per_transaction(&config) == 50, 1);
            
            // Update to 1 for strict testing
            coin_flip::update_max_games_per_transaction(&admin_cap, &mut config, 1, ctx(&mut scenario));
            assert!(coin_flip::get_max_games_per_transaction(&config) == 1, 2);
            
            // Update back to reasonable value
            coin_flip::update_max_games_per_transaction(&admin_cap, &mut config, 25, ctx(&mut scenario));
            assert!(coin_flip::get_max_games_per_transaction(&config) == 25, 3);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidMaxGames)]
    fun test_invalid_max_games_zero() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to set limit to 0 - should fail
            coin_flip::update_max_games_per_transaction(&admin_cap, &mut config, 0, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidMaxGames)]
    fun test_invalid_max_games_too_high() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to set limit above 1000 - should fail
            coin_flip::update_max_games_per_transaction(&admin_cap, &mut config, 1001, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETooManyGames)]
    fun test_bulk_join_exceeds_max_games_limit() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Admin sets max games limit to 1
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::update_max_games_per_transaction(&admin_cap, &mut config, 1, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Player 1 creates two games
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create first game
            let bet_coin1 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin1, true, &config, &clock, ctx(&mut scenario));
            
            // Create second game
            let bet_coin2 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin2, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Player 2 tries to join both games when limit is 1 (should fail)
        next_tx(&mut scenario, PLAYER2);
        {
            let game1 = test::take_shared<Game<SUI>>(&scenario);
            let game2 = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector of 2 games (exceeds limit of 1)
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game1);
            vector::push_back(&mut games, game2);
            
            // Create payment for both games
            let payment = coin::mint_for_testing<SUI>(2 * TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Try to join 2 games when limit is 1 (should fail with ETooManyGames)
            coin_flip::join_games(games, payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    fun test_bulk_join_within_max_games_limit() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object using system address
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Admin sets max games limit to 2
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::update_max_games_per_transaction(&admin_cap, &mut config, 2, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Player 1 creates two games
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create first game
            let bet_coin1 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin1, true, &config, &clock, ctx(&mut scenario));
            
            // Create second game
            let bet_coin2 = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin2, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Update randomness state
        next_tx(&mut scenario, SYSTEM);
        {
            let mut rnd = test::take_shared<random::Random>(&scenario);
            
            random::update_randomness_state_for_testing(
                &mut rnd, 
                0, 
                x"0000000000000000000000000000000000000000000000000000000000000000", 
                ctx(&mut scenario)
            );
            
            test::return_shared(rnd);
        };

        // Player 2 joins both games (exactly at the limit of 2)
        next_tx(&mut scenario, PLAYER2);
        {
            let game1 = test::take_shared<Game<SUI>>(&scenario);
            let game2 = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            // Create vector of 2 games (exactly at limit)
            let mut games = vector::empty<Game<SUI>>();
            vector::push_back(&mut games, game1);
            vector::push_back(&mut games, game2);
            
            // Create payment for both games
            let payment = coin::mint_for_testing<SUI>(2 * TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Join both games (should succeed since we're at the limit)
            coin_flip::join_games(games, payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidAdminCap)]
    fun test_non_admin_cannot_update_max_games() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, PLAYER1);
        {
            // Create a fake admin cap
            let fake_admin_cap = coin_flip::create_admin_cap_for_testing(ctx(&mut scenario));
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to update max games with fake admin cap (should fail)
            coin_flip::update_max_games_per_transaction(&fake_admin_cap, &mut config, 50, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, fake_admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }
} 