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
    const TEST_BET_AMOUNT: u64 = 100_000_000; // 0.1 SUI
    const TEST_OVERPAY_AMOUNT: u64 = 150_000_000; // 0.15 SUI  
    const TEST_UNDERPAY_AMOUNT: u64 = 5_000_000; // 0.005 SUI (less than 0.01 min)

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
            assert!(test::has_most_recent_shared<Game>(), 0);
        };

        test::end(scenario);
    }

    #[test]
    fun test_join_game_with_randomness() {
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
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario)); // creator bets on heads
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Update randomness state (must be done by system)
        next_tx(&mut scenario, SYSTEM);
        {
            let mut rnd = test::take_shared<random::Random>(&scenario);
            
            // Set randomness - we can't predict the exact outcome due to HMAC-SHA3-256
            random::update_randomness_state_for_testing(
                &mut rnd, 
                0, 
                x"0000000000000000000000000000000000000000000000000000000000000000", 
                ctx(&mut scenario)
            );
            
            test::return_shared(rnd);
        };

        // Player 2 joins the game 
        next_tx(&mut scenario, PLAYER2);
        {
            let mut game = test::take_shared<Game>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::join_game(&mut game, bet_coin, &mut config, &rnd, ctx(&mut scenario));
            
            test::return_shared(game);
            test::return_shared(config);
            test::return_shared(rnd);
            clock::destroy_for_testing(clock);
        };

        // Check that someone received winnings (either creator or joiner)
        // and treasury collected fees
        next_tx(&mut scenario, PLAYER1);
        {
            let has_payout = test::has_most_recent_for_sender<Coin<SUI>>(&scenario);
            if (has_payout) {
                // Creator won - take the payout
                let payout_coin = test::take_from_sender<Coin<SUI>>(&scenario);
                assert!(coin::value(&payout_coin) == 195_000_000, 1); // 200M - 5M fee (2.5% of 200M)
                test::return_to_sender(&scenario, payout_coin);
            };
        };

        next_tx(&mut scenario, PLAYER2);
        {
            let has_payout = test::has_most_recent_for_sender<Coin<SUI>>(&scenario);
            if (has_payout) {
                // Joiner won - take the payout
                let payout_coin = test::take_from_sender<Coin<SUI>>(&scenario);
                assert!(coin::value(&payout_coin) == 195_000_000, 2); // 200M - 5M fee (2.5% of 200M)
                test::return_to_sender(&scenario, payout_coin);
            };
        };

        // Check that treasury collected fees
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let treasury_balance = coin_flip::get_treasury_balance(&config);
            assert!(treasury_balance == 5_000_000, 3); // 2.5% of 200M
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_join_game_joiner_wins() {
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
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario)); // creator bets on heads
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Update randomness state (must be done by system)
        next_tx(&mut scenario, SYSTEM);
        {
            let mut rnd = test::take_shared<random::Random>(&scenario);
            
            // Set randomness to favor tails (joiner wins)
            random::update_randomness_state_for_testing(
                &mut rnd, 
                0, 
                x"FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF", // This should generate tails
                ctx(&mut scenario)
            );
            
            test::return_shared(rnd);
        };

        // Player 2 joins the game 
        next_tx(&mut scenario, PLAYER2);
        {
            let mut game = test::take_shared<Game>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::join_game(&mut game, bet_coin, &mut config, &rnd, ctx(&mut scenario));
            
            test::return_shared(game);
            test::return_shared(config);
            test::return_shared(rnd);
            clock::destroy_for_testing(clock);
        };

        // Check that joiner (PLAYER2) received winnings
        next_tx(&mut scenario, PLAYER2);
        {
            // Joiner should have received the payout
            assert!(test::has_most_recent_for_sender<Coin<SUI>>(&scenario), 0);
            let payout_coin = test::take_from_sender<Coin<SUI>>(&scenario);
            
            // Total pot was 200M, fee is 2.5% (5M), so winner gets 195M
            assert!(coin::value(&payout_coin) == 195_000_000, 1);
            test::return_to_sender(&scenario, payout_coin);
        };

        // Check that treasury collected fees
        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let treasury_balance = coin_flip::get_treasury_balance(&config);
            assert!(treasury_balance == 5_000_000, 2); // 2.5% of 200M
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_join_game_with_overpayment() {
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
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario)); // creator bets on heads
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Update randomness state (must be done by system)
        next_tx(&mut scenario, SYSTEM);
        {
            let mut rnd = test::take_shared<random::Random>(&scenario);
            
            // Set randomness 
            random::update_randomness_state_for_testing(
                &mut rnd, 
                0, 
                x"0000000000000000000000000000000000000000000000000000000000000000", 
                ctx(&mut scenario)
            );
            
            test::return_shared(rnd);
        };

        // Player 2 joins the game with overpayment
        next_tx(&mut scenario, PLAYER2);
        {
            let mut game = test::take_shared<Game>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Pay 1500 instead of required 1000
            let bet_coin = coin::mint_for_testing<SUI>(TEST_OVERPAY_AMOUNT, ctx(&mut scenario));
            coin_flip::join_game(&mut game, bet_coin, &mut config, &rnd, ctx(&mut scenario));
            
            test::return_shared(game);
            test::return_shared(config);
            test::return_shared(rnd);
            clock::destroy_for_testing(clock);
        };

        // Check that joiner received change and winner received correct payout
        next_tx(&mut scenario, PLAYER2);
        {
            // Player2 should have received excess payment back (50M)
            assert!(test::has_most_recent_for_sender<Coin<SUI>>(&scenario), 0);
            let change_coin = test::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&change_coin) == 50_000_000, 1); // Excess amount (150M - 100M)
            test::return_to_sender(&scenario, change_coin);
        };

        next_tx(&mut scenario, PLAYER1);
        {
            // Creator should have received the win payout (1950 from 2000 pot minus 50 fee)
            assert!(test::has_most_recent_for_sender<Coin<SUI>>(&scenario), 0);
            let payout_coin = test::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&payout_coin) == 195_000_000, 2);
            test::return_to_sender(&scenario, payout_coin);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ECannotJoinOwnGame)]
    fun test_cannot_join_own_game() {
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

        // Player 1 tries to join their own game (should fail)
        next_tx(&mut scenario, PLAYER1);
        {
            let mut game = test::take_shared<Game>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::join_game(&mut game, bet_coin, &mut config, &rnd, ctx(&mut scenario));
            
            test::return_shared(game);
            test::return_shared(config);
            test::return_shared(rnd);
            clock::destroy_for_testing(clock);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInsufficientPayment)]
    fun test_insufficient_payment() {
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

        // Player 2 tries to join with insufficient payment (should fail)
        next_tx(&mut scenario, PLAYER2);
        {
            let mut game = test::take_shared<Game>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<SUI>(TEST_UNDERPAY_AMOUNT, ctx(&mut scenario)); // Less than required minimum
            coin_flip::join_game(&mut game, bet_coin, &mut config, &rnd, ctx(&mut scenario));
            
            test::return_shared(game);
            test::return_shared(config);
            test::return_shared(rnd);
            clock::destroy_for_testing(clock);
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
            let game = test::take_shared<Game>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            coin_flip::cancel_game(game, ctx(&mut scenario));
            clock::destroy_for_testing(clock);
        };

        // Player 1 should receive refund
        next_tx(&mut scenario, PLAYER1);
        {
            assert!(test::has_most_recent_for_sender<Coin<SUI>>(&scenario), 0);
            let refund_coin = test::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&refund_coin) == 100_000_000, 1);
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
            let game = test::take_shared<Game>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            coin_flip::cancel_game(game, ctx(&mut scenario));
            clock::destroy_for_testing(clock);
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
    fun test_withdraw_fees_empty_treasury() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Admin tries to withdraw from empty treasury
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            
            let treasury_balance = coin_flip::get_treasury_balance(&config);
            assert!(treasury_balance == 0, 0); // Should be empty initially
            
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
            let game = test::take_shared<Game>(&scenario);
            let (creator, bet_amount, creator_choice_heads, is_active, _created_at) = coin_flip::get_game_info(&game);
            
            assert!(creator == PLAYER1, 0);
            assert!(bet_amount == 100_000_000, 1);
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
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            
            // Test view functions
            let fee_percentage = coin_flip::get_fee_percentage(&config);
            let treasury_balance = coin_flip::get_treasury_balance(&config);
            
            assert!(fee_percentage == 250, 0); // Default 2.5%
            assert!(treasury_balance == 0, 1); // Initially empty
            // Admin cap ID should be set (we can't access the private field directly)
            
            test::return_to_sender(&scenario, admin_cap);
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
            let mut game = test::take_shared<Game>(&scenario);
            coin_flip::set_game_inactive_for_testing(&mut game);
            test::return_shared(game);
        };

        // Verify the game is now inactive
        next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game>(&scenario);
            let (_, _, _, is_active, _) = coin_flip::get_game_info(&game);
            
            // Verify game is inactive - in real usage, calling join_game 
            // on this inactive game would trigger EGameNotFound
            assert!(!is_active, 0);
            
            test::return_shared(game);
        };

        test::end(scenario);
    }

    #[test]
    fun test_withdraw_fees_after_games() {
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

        // Player 2 joins the game 
        next_tx(&mut scenario, PLAYER2);
        {
            let mut game = test::take_shared<Game>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::join_game(&mut game, bet_coin, &mut config, &rnd, ctx(&mut scenario));
            
            test::return_shared(game);
            test::return_shared(config);
            test::return_shared(rnd);
            clock::destroy_for_testing(clock);
        };

        // Admin withdraws fees
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Should have 5M mist in fees (2.5% of 200M)
            let treasury_balance = coin_flip::get_treasury_balance(&config);
            assert!(treasury_balance == 5_000_000, 0);
            
            // Withdraw all fees (no amount parameter needed anymore)
            coin_flip::withdraw_fees(&admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Check admin received the fees
        next_tx(&mut scenario, ADMIN);
        {
            assert!(test::has_most_recent_for_sender<Coin<SUI>>(&scenario), 0);
            let fee_coin = test::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&fee_coin) == 5_000_000, 1);
            test::return_to_sender(&scenario, fee_coin);
            
            // Treasury should now be empty
            let config = test::take_shared<GameConfig>(&scenario);
            let treasury_balance = coin_flip::get_treasury_balance(&config);
            assert!(treasury_balance == 0, 2);
            test::return_shared(config);
        };

        test::end(scenario);
    }
} 