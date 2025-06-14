#[test_only]
module sui_coin_flip::coin_flip_error_coverage_tests {
    use sui::test_scenario::{Self as test};
    use sui::coin;
    use sui::sui::SUI;
    use sui::clock::{Self};
    use sui::random;
    
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

    // Test tokens for error coverage
    public struct DISABLED_TOKEN has drop {}
    public struct NON_WHITELISTED_TOKEN has drop {}
    public struct TOKEN_A has drop {}
    public struct TOKEN_B has drop {}
    
    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidAddress)]
    fun test_update_treasury_address_zero_address_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to set treasury address to zero address (should fail with EInvalidAddress)
            coin_flip::update_treasury_address(&admin_cap, &mut config, @0x0, test::ctx(&mut scenario));
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETokenNotWhitelisted)]
    fun test_update_token_limits_for_non_whitelisted_token_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to update token limits for non-whitelisted token 
            // (should fail with ETokenNotWhitelisted)
            coin_flip::update_token_limits<NON_WHITELISTED_TOKEN>(
                &admin_cap, 
                &mut config, 
                1000, 
                2000, 
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETokenNotWhitelisted)]
    fun test_set_token_enabled_for_non_whitelisted_token_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to enable/disable non-whitelisted token 
            // (should fail with ETokenNotWhitelisted)
            coin_flip::set_token_enabled<NON_WHITELISTED_TOKEN>(
                &admin_cap, 
                &mut config, 
                false, 
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETokenNotWhitelisted)]
    fun test_create_game_with_disabled_token_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Admin adds token to whitelist
            coin_flip::add_whitelisted_token<DISABLED_TOKEN>(
                &admin_cap, 
                &mut config, 
                1000, 
                2000, 
                test::ctx(&mut scenario)
            );
            
            // Admin disables the token (token_config.enabled = false)
            coin_flip::set_token_enabled<DISABLED_TOKEN>(
                &admin_cap, 
                &mut config, 
                false, 
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Try to create game with disabled token (should fail with ETokenNotWhitelisted)
        test::next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(test::ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<DISABLED_TOKEN>(1500, test::ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, test::ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETokenNotWhitelisted)]
    fun test_join_games_with_disabled_token_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Admin adds token to whitelist with enabled = true
            coin_flip::add_whitelisted_token<DISABLED_TOKEN>(
                &admin_cap, 
                &mut config, 
                1000, 
                2000, 
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Player 1 creates game with enabled token
        test::next_tx(&mut scenario, PLAYER1);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            let clock = clock::create_for_testing(test::ctx(&mut scenario));
            
            let bet_coin = coin::mint_for_testing<DISABLED_TOKEN>(1500, test::ctx(&mut scenario));
            coin_flip::create_game(bet_coin, true, &config, &clock, test::ctx(&mut scenario));
            
            test::return_shared(config);
            clock::destroy_for_testing(clock);
        };

        // Admin disables the token after game creation
        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            coin_flip::set_token_enabled<DISABLED_TOKEN>(
                &admin_cap, 
                &mut config, 
                false, 
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Create Random object for join_games
        test::next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(test::ctx(&mut scenario));
        };

        // Player 2 tries to join with disabled token 
        // (should fail with ETokenNotWhitelisted due to token_config.enabled = false)
        test::next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game<DISABLED_TOKEN>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            let mut games = vector::empty<Game<DISABLED_TOKEN>>();
            vector::push_back(&mut games, game);
            
            let payment = coin::mint_for_testing<DISABLED_TOKEN>(1500, test::ctx(&mut scenario));
            coin_flip::join_games(games, payment, &config, &rnd, test::ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::ETokenMismatch)]
    fun test_join_games_with_mismatched_token_type_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Add TOKEN_A to whitelist
            coin_flip::add_whitelisted_token<TOKEN_A>(
                &admin_cap, 
                &mut config, 
                1000, 
                2000, 
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        // Create Random object for join_games
        test::next_tx(&mut scenario, SYSTEM);
        {
            random::create_for_testing(test::ctx(&mut scenario));
        };

        // Create a game with TOKEN_A but set wrong token_type internally 
        // (using test helper to simulate inconsistent state)
        test::next_tx(&mut scenario, PLAYER1);
        {
            let clock = clock::create_for_testing(test::ctx(&mut scenario));
            let bet_coin = coin::mint_for_testing<TOKEN_A>(1500, test::ctx(&mut scenario));
            
            // Create game with TOKEN_A but wrong token_type (TOKEN_B's type name)
            let wrong_token_type = std::type_name::get<TOKEN_B>();
            coin_flip::create_game_with_wrong_token_type_for_testing(
                bet_coin, 
                true, 
                wrong_token_type, 
                &clock, 
                test::ctx(&mut scenario)
            );
            
            clock::destroy_for_testing(clock);
        };

        // Player 2 tries to join the corrupted game (should fail with ETokenMismatch)
        test::next_tx(&mut scenario, PLAYER2);
        {
            let game = test::take_shared<Game<TOKEN_A>>(&scenario);
            let config = test::take_shared<GameConfig>(&scenario);
            let rnd = test::take_shared<random::Random>(&scenario);
            
            let mut games = vector::empty<Game<TOKEN_A>>();
            vector::push_back(&mut games, game);
            
            let payment = coin::mint_for_testing<TOKEN_A>(1500, test::ctx(&mut scenario));
            coin_flip::join_games(games, payment, &config, &rnd, test::ctx(&mut scenario));
            
            test::return_shared(config);
            test::return_shared(rnd);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidBetAmount)]
    fun test_add_whitelisted_token_zero_min_bet_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to add token with zero min bet amount (should fail with EInvalidBetAmount)
            coin_flip::add_whitelisted_token<TOKEN_A>(
                &admin_cap, 
                &mut config, 
                0, // Zero min bet amount - invalid
                2000, 
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = coin_flip::EInvalidBetAmount)]
    fun test_add_whitelisted_token_min_greater_than_max_error() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Try to add token with min bet amount greater than max bet amount 
            // (should fail with EInvalidBetAmount)
            coin_flip::add_whitelisted_token<TOKEN_A>(
                &admin_cap, 
                &mut config, 
                3000, // Min bet amount
                2000, // Max bet amount (less than min) - invalid
                test::ctx(&mut scenario)
            );
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_get_token_config_view_function() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Test 1: Non-whitelisted token should return (false, 0, 0)
            let (enabled, min_bet, max_bet) = coin_flip::get_token_config<TOKEN_A>(&config);
            assert!(enabled == false, 0);
            assert!(min_bet == 0, 1);
            assert!(max_bet == 0, 2);
            
            // Test 2: Add TOKEN_A to whitelist with specific values
            coin_flip::add_whitelisted_token<TOKEN_A>(
                &admin_cap, 
                &mut config, 
                1500, // min_bet_amount
                3000, // max_bet_amount 
                test::ctx(&mut scenario)
            );
            
            // Should now return correct values for whitelisted token
            let (enabled, min_bet, max_bet) = coin_flip::get_token_config<TOKEN_A>(&config);
            assert!(enabled == true, 3);
            assert!(min_bet == 1500, 4);
            assert!(max_bet == 3000, 5);
            
            // Test 3: Disable the token and verify enabled=false but limits remain
            coin_flip::set_token_enabled<TOKEN_A>(&admin_cap, &mut config, false, test::ctx(&mut scenario));
            let (enabled, min_bet, max_bet) = coin_flip::get_token_config<TOKEN_A>(&config);
            assert!(enabled == false, 6); // Now disabled
            assert!(min_bet == 1500, 7);   // Limits unchanged
            assert!(max_bet == 3000, 8);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_get_token_bet_limits_view_function() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = test::take_from_sender<AdminCap>(&scenario);
            let mut config = test::take_shared<GameConfig>(&scenario);
            
            // Test 1: Non-whitelisted token should return (0, 0)
            let (min_bet, max_bet) = coin_flip::get_token_bet_limits<TOKEN_B>(&config);
            assert!(min_bet == 0, 0);
            assert!(max_bet == 0, 1);
            
            // Test 2: Add TOKEN_B to whitelist with specific limits
            coin_flip::add_whitelisted_token<TOKEN_B>(
                &admin_cap, 
                &mut config, 
                2500, // min_bet_amount
                5000, // max_bet_amount
                test::ctx(&mut scenario)
            );
            
            // Should now return correct limits for whitelisted token
            let (min_bet, max_bet) = coin_flip::get_token_bet_limits<TOKEN_B>(&config);
            assert!(min_bet == 2500, 2);
            assert!(max_bet == 5000, 3);
            
            // Test 3: Update the limits and verify changes
            coin_flip::update_token_limits<TOKEN_B>(
                &admin_cap,
                &mut config,
                1000, // new min_bet_amount
                8000, // new max_bet_amount
                test::ctx(&mut scenario)
            );
            
            let (min_bet, max_bet) = coin_flip::get_token_bet_limits<TOKEN_B>(&config);
            assert!(min_bet == 1000, 4); // Updated min
            assert!(max_bet == 8000, 5);  // Updated max
            
            // Test 4: Disable token and verify limits still accessible
            coin_flip::set_token_enabled<TOKEN_B>(&admin_cap, &mut config, false, test::ctx(&mut scenario));
            let (min_bet, max_bet) = coin_flip::get_token_bet_limits<TOKEN_B>(&config);
            assert!(min_bet == 1000, 6); // Limits remain even when disabled
            assert!(max_bet == 8000, 7);
            
            test::return_to_sender(&scenario, admin_cap);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_view_functions_with_sui_default_token() {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize contract
        {
            coin_flip::init_for_testing(test::ctx(&mut scenario));
        };

        test::next_tx(&mut scenario, ADMIN);
        {
            let config = test::take_shared<GameConfig>(&scenario);
            
            // Test that SUI is whitelisted by default with correct values
            let (enabled, min_bet, max_bet) = coin_flip::get_token_config<SUI>(&config);
            assert!(enabled == true, 0);
            assert!(min_bet == 20_000_0000, 1); // MIN_BET_AMOUNT (0.2 SUI)
            assert!(max_bet == 1_000_000_000_000, 2); // MAX_BET_AMOUNT (1000 SUI)
            
            // Test get_token_bet_limits for SUI
            let (min_bet, max_bet) = coin_flip::get_token_bet_limits<SUI>(&config);
            assert!(min_bet == 20_000_0000, 3);
            assert!(max_bet == 1_000_000_000_000, 4);
            
            test::return_shared(config);
        };

        test::end(scenario);
    }
} 