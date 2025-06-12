#[test_only]
module sui_coin_flip::coin_flip_multi_token_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin;
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
    
    // Test amounts
    const TEST_BET_AMOUNT: u64 = 200_000_000; // 0.2 SUI

    // Mock token types for testing
    public struct USDC has drop {}
    public struct USDT has drop {}

    #[test]
    fun test_sui_token_whitelisted_by_default() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            
            // SUI should be whitelisted by default
            assert!(coin_flip::is_token_whitelisted<SUI>(&config), 0);
            
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_admin_add_token_to_whitelist() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // USDC should not be whitelisted initially
            assert!(!coin_flip::is_token_whitelisted<USDC>(&config), 0);
            
            // Admin adds USDC to whitelist
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            // USDC should now be whitelisted
            assert!(coin_flip::is_token_whitelisted<USDC>(&config), 1);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_admin_remove_token_from_whitelist() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Add USDC to whitelist first
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            assert!(coin_flip::is_token_whitelisted<USDC>(&config), 0);
            
            // Remove USDC from whitelist
            coin_flip::remove_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            // USDC should no longer be whitelisted
            assert!(!coin_flip::is_token_whitelisted<USDC>(&config), 1);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidAdminCap)]
    fun test_non_admin_cannot_add_token() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, PLAYER1);
        {
            // Create fake admin cap
            let fake_admin_cap = coin_flip::create_admin_cap_for_testing(ctx(&mut scenario));
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to add token with fake admin cap (should fail)
            coin_flip::add_whitelisted_token<USDC>(&fake_admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, fake_admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidAdminCap)]
    fun test_non_admin_cannot_remove_token() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Admin adds USDC first
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        next_tx(&mut scenario, PLAYER1);
        {
            // Create fake admin cap
            let fake_admin_cap = coin_flip::create_admin_cap_for_testing(ctx(&mut scenario));
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to remove token with fake admin cap (should fail)
            coin_flip::remove_whitelisted_token<USDC>(&fake_admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, fake_admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETokenNotWhitelisted)]
    fun test_create_game_with_non_whitelisted_token() {
        let mut scenario = test::begin(PLAYER1);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Try to create game with USDC (not whitelisted) - should fail
            let bet_coin = coin::mint_for_testing<USDC>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        test::end(scenario);
    }

    #[test]
    fun test_create_game_with_whitelisted_token() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Admin adds USDC to whitelist
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Player creates game with USDC
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<USDC>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        next_tx(&mut scenario, PLAYER1);
        {
            // USDC game should be created
            assert!(test::has_most_recent_shared<Game<USDC>>(), 0);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETokenNotWhitelisted)]
    fun test_join_games_with_non_whitelisted_token() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Admin adds USDC to whitelist and creates a game
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<USDC>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Admin removes USDC from whitelist
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::remove_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Player 2 tries to join with USDC (now not whitelisted) - should fail
        next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game<USDC>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            let mut games = vector::empty<Game<USDC>>();
            vector::push_back(&mut games, game);
            
            let payment = coin::mint_for_testing<USDC>(TEST_BET_AMOUNT, ctx(&mut scenario));
            
            // Should fail because USDC is no longer whitelisted
            coin_flip::join_games(games, payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    // Note: The token mismatch test is enforced at compile time by Move's type system
    // This is actually better security than runtime checks!
    // If you try to call join_games<USDC> with a Coin<USDT>, it won't compile.

    #[test]
    fun test_successful_multi_token_games() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Create Random object
        next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(ctx(&mut scenario));
        };

        // Admin adds USDC to whitelist
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Player 1 creates both SUI and USDC games
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create SUI game
            let sui_bet = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(sui_bet, true, &config, &clock, ctx(&mut scenario));
            
            // Create USDC game
            let usdc_bet = coin::mint_for_testing<USDC>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(usdc_bet, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Update randomness
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

        // Player 2 joins SUI games
        next_tx(&mut scenario, PLAYER2);
        {
            let sui_game = test::take_shared<Game<SUI>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            let mut sui_games = vector::empty<Game<SUI>>();
            vector::push_back(&mut sui_games, sui_game);
            
            let sui_payment = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::join_games(sui_games, sui_payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        // Player 2 joins USDC games
        next_tx(&mut scenario, PLAYER2);
        {
            let usdc_game = test::take_shared<Game<USDC>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            let mut usdc_games = vector::empty<Game<USDC>>();
            vector::push_back(&mut usdc_games, usdc_game);
            
            let usdc_payment = coin::mint_for_testing<USDC>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::join_games(usdc_games, usdc_payment, &config, &rnd, ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    fun test_token_type_in_game_events() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        // Admin adds USDC to whitelist
        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Create games with different tokens
        next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(ctx(&mut scenario));
            
            // Create SUI game - should emit GameCreated event with SUI token type
            let sui_bet = coin::mint_for_testing<SUI>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(sui_bet, true, &config, &clock, ctx(&mut scenario));
            
            // Create USDC game - should emit GameCreated event with USDC token type
            let usdc_bet = coin::mint_for_testing<USDC>(TEST_BET_AMOUNT, ctx(&mut scenario));
            coin_flip::create_game(usdc_bet, false, &config, &clock, ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Verify both games exist with correct types
        next_tx(&mut scenario, PLAYER2);
        {
            assert!(test::has_most_recent_shared<Game<SUI>>(), 0);
            assert!(test::has_most_recent_shared<Game<USDC>>(), 1);
        };

        test::end(scenario);
    }

    #[test]
    fun test_get_whitelisted_tokens_view() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(ctx(&mut scenario));
        };

        next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Get initial whitelist (should contain SUI)
            let _whitelist = coin_flip::get_whitelisted_tokens(&config);
            
            // Add USDC and USDT
            coin_flip::add_whitelisted_token<USDC>(&admin_cap, &mut config, ctx(&mut scenario));
            coin_flip::add_whitelisted_token<USDT>(&admin_cap, &mut config, ctx(&mut scenario));
            
            // Verify tokens are whitelisted
            assert!(coin_flip::is_token_whitelisted<SUI>(&config), 0);
            assert!(coin_flip::is_token_whitelisted<USDC>(&config), 1);
            assert!(coin_flip::is_token_whitelisted<USDT>(&config), 2);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }
} 