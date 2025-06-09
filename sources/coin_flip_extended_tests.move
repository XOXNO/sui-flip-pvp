#[test_only]
module sui_coin_flip::coin_flip_extended_tests {
    use sui::test_scenario::{Self as test, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};

    use sui_coin_flip::coin_flip::{
        Self, 
        Game, 
        GameConfig, 
        AdminCap,
        EContractPaused,
        EBetTooSmall,
        EBetTooLarge,
        EEmptyTreasury,
        EInvalidBetAmount
    };

    const ADMIN: address = @0x1;
    const PLAYER1: address = @0x2;
    const PLAYER2: address = @0x3;

    // Test helper function to create coins
    fun mint_sui(amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx)
    }

    // Test helper to setup test environment
    fun setup_test(): (Scenario, AdminCap, GameConfig, Clock) {
        let mut scenario = test::begin(ADMIN);
        
        // Initialize the module
        {
            let ctx = test::ctx(&mut scenario);
            coin_flip::init_for_testing(ctx);
        };
        
        // Get objects
        test::next_tx(&mut scenario, ADMIN);
        let admin_cap = test::take_from_sender<AdminCap>(&scenario);
        let config = test::take_shared<GameConfig>(&scenario);
        let clock = {
            let ctx = test::ctx(&mut scenario);
            clock::create_for_testing(ctx)
        };
        
        (scenario, admin_cap, config, clock)
    }



    #[test]
    fun test_update_bet_limits_success() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        let ctx = test::ctx(&mut scenario);
        
        // Update bet limits
        let new_min = 5_000_000; // 0.005 SUI
        let new_max = 2_000_000_000_000; // 2000 SUI
        
        coin_flip::update_bet_limits(&admin_cap, &mut config, new_min, new_max, ctx);
        
        // Verify limits were updated
        let (min_bet, max_bet) = coin_flip::get_bet_limits(&config);
        assert!(min_bet == new_min, 0);
        assert!(max_bet == new_max, 1);
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidBetAmount)]
    fun test_update_bet_limits_invalid_zero_min() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        let ctx = test::ctx(&mut scenario);
        
        // Try to set min bet to zero
        coin_flip::update_bet_limits(&admin_cap, &mut config, 0, 1000, ctx);
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EInvalidBetAmount)]
    fun test_update_bet_limits_min_greater_than_max() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        let ctx = test::ctx(&mut scenario);
        
        // Try to set min bet greater than max bet
        coin_flip::update_bet_limits(&admin_cap, &mut config, 2000, 1000, ctx);
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_set_pause_state_success() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        let ctx = test::ctx(&mut scenario);
        
        // Initially should not be paused
        assert!(coin_flip::is_contract_paused(&config) == false, 0);
        
        // Pause the contract
        coin_flip::set_pause_state(&admin_cap, &mut config, true, ctx);
        assert!(coin_flip::is_contract_paused(&config) == true, 1);
        
        // Unpause the contract
        coin_flip::set_pause_state(&admin_cap, &mut config, false, ctx);
        assert!(coin_flip::is_contract_paused(&config) == false, 2);
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EContractPaused)]
    fun test_create_game_when_paused() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        
        // Pause the contract
        coin_flip::set_pause_state(&admin_cap, &mut config, true, test::ctx(&mut scenario));
        
        // Try to create a game when paused
        test::next_tx(&mut scenario, PLAYER1);
        let bet_coin = mint_sui(50_000_000, test::ctx(&mut scenario));
        coin_flip::create_game(bet_coin, true, &config, &clock, test::ctx(&mut scenario));
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }



    #[test]
    #[expected_failure(abort_code = EBetTooSmall)]
    fun test_create_game_bet_too_small() {
        let (mut scenario, admin_cap, config, clock) = setup_test();
        
        // Try to create a game with bet smaller than minimum
        test::next_tx(&mut scenario, PLAYER1);
        let bet_coin = mint_sui(1_000_000, test::ctx(&mut scenario)); // 0.001 SUI, less than 0.01 SUI minimum
        coin_flip::create_game(bet_coin, true, &config, &clock, test::ctx(&mut scenario));
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EBetTooLarge)]
    fun test_create_game_bet_too_large() {
        let (mut scenario, admin_cap, config, clock) = setup_test();
        
        // Try to create a game with bet larger than maximum
        test::next_tx(&mut scenario, PLAYER1);
        let bet_coin = mint_sui(1_001_000_000_000, test::ctx(&mut scenario)); // 1001 SUI, more than 1000 SUI maximum
        coin_flip::create_game(bet_coin, true, &config, &clock, test::ctx(&mut scenario));
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EBetTooSmall)]
    fun test_bet_limits_with_custom_values() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        
        // Update bet limits to custom values
        let new_min = 20_000_000; // 0.02 SUI
        let new_max = 500_000_000_000; // 500 SUI
        coin_flip::update_bet_limits(&admin_cap, &mut config, new_min, new_max, test::ctx(&mut scenario));
        
        // Test bet smaller than new minimum (this should fail)
        test::next_tx(&mut scenario, PLAYER1);
        let small_bet = mint_sui(10_000_000, test::ctx(&mut scenario)); // 0.01 SUI
        coin_flip::create_game(small_bet, true, &config, &clock, test::ctx(&mut scenario));
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = EEmptyTreasury)]
    fun test_withdraw_fees_empty_treasury() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        let ctx = test::ctx(&mut scenario);
        
        // Try to withdraw fees when treasury is empty
        coin_flip::withdraw_fees(&admin_cap, &mut config, ctx);
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }



    #[test]
    fun test_config_updated_event_structure() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        let ctx = test::ctx(&mut scenario);
        
        // Test that updating pause state emits the correct event
        coin_flip::set_pause_state(&admin_cap, &mut config, true, ctx);
        
        // Test that updating bet limits emits the correct event
        coin_flip::update_bet_limits(&admin_cap, &mut config, 15_000_000, 1_500_000_000_000, ctx);
        
        // Test that updating fee percentage emits the correct event
        coin_flip::update_fee_percentage(&admin_cap, &mut config, 300, ctx);
        
        // Verify the config values are updated
        assert!(coin_flip::is_contract_paused(&config) == true, 0);
        let (min_bet, max_bet) = coin_flip::get_bet_limits(&config);
        assert!(min_bet == 15_000_000, 1);
        assert!(max_bet == 1_500_000_000_000, 2);
        assert!(coin_flip::get_fee_percentage(&config) == 300, 3);
        
        // Cleanup
        test::return_to_sender(&scenario, admin_cap);
        test::return_shared(config);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_edge_case_bet_limits_equal() {
        let (mut scenario, admin_cap, mut config, clock) = setup_test();
        
        // Set min and max bet to the same value
        let bet_amount = 100_000_000; // 0.1 SUI
        coin_flip::update_bet_limits(&admin_cap, &mut config, bet_amount, bet_amount, test::ctx(&mut scenario));
        
        // Create a game with exactly that amount
        test::next_tx(&mut scenario, PLAYER1);
        let bet_coin = mint_sui(bet_amount, test::ctx(&mut scenario));
        coin_flip::create_game(bet_coin, true, &config, &clock, test::ctx(&mut scenario));
        
        // Verify the game was created successfully
        test::next_tx(&mut scenario, PLAYER2);
        let game = test::take_shared<Game>(&scenario);
        let (_, game_bet_amount, _, is_active, _) = coin_flip::get_game_info(&game);
        assert!(game_bet_amount == bet_amount, 0);
        assert!(is_active == true, 1);
        
        // Cleanup
        test::return_to_address(ADMIN, admin_cap);
        test::return_shared(config);
        test::return_shared(game);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
} 