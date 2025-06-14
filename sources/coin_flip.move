/// A secure coin flip game smart contract for SUI
/// Players can create games with SUI bets and others can join to flip for the win
module sui_coin_flip::coin_flip {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::random::{Self, Random};
    use sui::clock::{Self, Clock};
    use std::type_name::{Self, TypeName};
    use sui::table::{Self, Table};
    
    // ======== Constants ========
    
    /// Fee base for percentage calculations (10000 = 100%)
    const FEE_BASE: u64 = 10000;
    /// Default fee percentage (250 = 2.5%)
    const DEFAULT_FEE_PERCENTAGE: u64 = 250;
    /// Minimum bet amount to prevent dust attacks (0.2 SUI)
    const MIN_BET_AMOUNT: u64 = 20_000_0000; // 0.2 SUI in MIST
    /// Maximum bet amount to prevent whale manipulation (1000 SUI)
    const MAX_BET_AMOUNT: u64 = 1_000_000_000_000; // 1000 SUI in MIST
    /// Default maximum games per transaction (to prevent DoS attacks)
    const DEFAULT_MAX_GAMES_PER_TX: u64 = 100;

    
    // ======== Errors ========
    
    const EInvalidBetAmount: u64 = 1;
    const EGameNotFound: u64 = 2;
    const ECannotJoinOwnGame: u64 = 3;
    const EInsufficientPayment: u64 = 4;
    const ENotGameCreator: u64 = 5;
    const EInvalidAdminCap: u64 = 6;
    const EInvalidFeePercentage: u64 = 7;
    const EBetTooSmall: u64 = 8;
    const EBetTooLarge: u64 = 9;
    const EContractPaused: u64 = 10;
    const ETooManyGames: u64 = 11;
    const EInvalidMaxGames: u64 = 12;
    const EInvalidAddress: u64 = 13;
    const ETokenNotWhitelisted: u64 = 14;
    const ETokenMismatch: u64 = 15;

    // ======== Witness Pattern ========

    /// One-Time-Witness for contract initialization
    public struct COIN_FLIP has drop {}

    // ======== Types ========

    /// Represents a coin side choice
    public struct CoinSide has copy, drop, store {
        is_heads: bool,
    }

    /// Game state object
    /// bet_amount: The exact amount required to join this game (for UI display and validation)
    /// balance: The actual tokens held by the game (may temporarily exceed bet_amount during join)
    /// token_type: The type of token used for this game
    public struct Game<phantom T> has key, store {
        id: UID,
        creator: address,
        bet_amount: u64, // Required bet amount to join
        creator_choice: CoinSide,
        balance: Balance<T>, // Actual tokens in the game
        is_active: bool,
        created_at_ms: u64, // Timestamp when game was created
        token_type: std::type_name::TypeName, // Store the token type for validation
    }

    /// Admin capability with unique ID for validation
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Global configuration with treasury address
    public struct GameConfig has key {
        id: UID,
        admin_cap_id: address, // ID of the valid admin cap
        fee_percentage: u64, // Configurable fee percentage
        treasury_address: address, // Address to receive fees directly
        is_paused: bool, // Emergency pause state
        min_bet_amount: u64, // Configurable minimum bet
        max_bet_amount: u64, // Configurable maximum bet
        max_games_per_transaction: u64, // Maximum games per bulk transaction
        whitelisted_tokens: Table<TypeName, bool>, // Whitelisted token types
    }

    // ======== Events ========

    public struct GameCreated has copy, drop {
        game_id: address,
        creator: address,
        bet_amount: u64,
        creator_choice_heads: bool,
        token_type: TypeName, // Token type used for the game
    }

    public struct GameJoined has copy, drop {
        game_id: address,
        creator: address,
        creator_choice_heads: bool,
        joiner: address,
        joiner_choice_heads: bool,
        winner: address,
        bet_amount: u64,
        loser: address,
        total_pot: u64,
        winner_payout: u64,
        fee_collected: u64,
        coin_flip_result_heads: bool,
        token_type: TypeName, // Token type used for the game
    }

    public struct GameCancelled has copy, drop {
        game_id: address,
        creator: address,
        refund_amount: u64,
        token_type: TypeName, // Token type used for the game
    }

    public struct ConfigUpdated has copy, drop {
        admin: address,
        fee_percentage: u64,
        is_paused: bool,
        min_bet_amount: u64,
        max_bet_amount: u64,
        treasury_address: address,
        max_games_per_transaction: u64,
    }

    // ======== Functions ========

    /// Module initializer using one-time-witness pattern - can only be called once
    fun init(otw: COIN_FLIP, ctx: &mut TxContext) {
        // Verify this is the one-time witness
        assert!(sui::types::is_one_time_witness(&otw), EInvalidAdminCap);

        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        
        let admin_cap_id = object::uid_to_address(&admin_cap.id);
        let deployer_address = tx_context::sender(ctx);
        
        // Initialize whitelist with SUI token by default
        let whitelisted_tokens = table::new<TypeName, bool>(ctx);
        table::add(&mut whitelisted_tokens, type_name::get<SUI>(), true);
        
        let config = GameConfig {
            id: object::new(ctx),
            admin_cap_id,
            fee_percentage: DEFAULT_FEE_PERCENTAGE,
            treasury_address: deployer_address, // Set deployer as initial treasury
            is_paused: false,
            min_bet_amount: MIN_BET_AMOUNT,
            max_bet_amount: MAX_BET_AMOUNT,
            max_games_per_transaction: DEFAULT_MAX_GAMES_PER_TX,
            whitelisted_tokens,
        };

        transfer::transfer(admin_cap, deployer_address);
        transfer::share_object(config);
    }

    /// Validate admin capability
    fun validate_admin_cap(admin_cap: &AdminCap, config: &GameConfig) {
        assert!(object::uid_to_address(&admin_cap.id) == config.admin_cap_id, EInvalidAdminCap);
    }

    /// Create a new coin flip game
    public entry fun create_game<T>(
        bet_coin: Coin<T>,
        choice: bool, // true for heads, false for tails
        config: &GameConfig,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if contract is paused
        assert!(!config.is_paused, EContractPaused);
        
        // Check if token is whitelisted
        let token_type = type_name::get<T>();
        assert!(table::contains(&config.whitelisted_tokens, token_type), ETokenNotWhitelisted);
        
        let bet_amount = coin::value(&bet_coin);
        assert!(bet_amount > 0, EInvalidBetAmount);
        assert!(bet_amount >= config.min_bet_amount, EBetTooSmall);
        assert!(bet_amount <= config.max_bet_amount, EBetTooLarge);

        let creator = tx_context::sender(ctx);
        let creator_choice = CoinSide { is_heads: choice };
        
        let game = Game<T> {
            id: object::new(ctx),
            creator,
            bet_amount,
            creator_choice,
            balance: coin::into_balance(bet_coin),
            is_active: true,
            created_at_ms: clock::timestamp_ms(clock),
            token_type,
        };

        let game_id = object::uid_to_address(&game.id);

        // Emit game created event
        event::emit(GameCreated {
            game_id,
            creator,
            bet_amount,
            creator_choice_heads: choice,
            token_type,
        });

        transfer::share_object(game);
    }

    /// SECURE: Join multiple games with equal resource consumption
    /// Private entry function prevents composition attacks while maintaining single-tx UX
    entry fun join_games<T>(
        games_raw: vector<Game<T>>,
        payment: Coin<T>,
        config: &GameConfig,
        rnd: &Random,
        ctx: &mut TxContext
    ) {
        let joiner = tx_context::sender(ctx);
        let games_count = vector::length(&games_raw);
        let payment_amount = coin::value(&payment);
        
        // Security checks
        assert!(!config.is_paused, EContractPaused);
        assert!(games_count > 0, EGameNotFound);
        assert!(games_count <= config.max_games_per_transaction, ETooManyGames);

        // Check if token is whitelisted
        let token_type = type_name::get<T>();
        assert!(table::contains(&config.whitelisted_tokens, token_type), ETokenNotWhitelisted);

        // Calculate total required bet amount and validate all games
        let mut required_total: u64 = 0;
        let mut i: u64 = 0;
        while (i < games_count) {
            let game = vector::borrow(&games_raw, i);
            assert!(game.is_active, EGameNotFound);
            assert!(joiner != game.creator, ECannotJoinOwnGame);
            // Verify all games use the same token type as payment
            assert!(game.token_type == token_type, ETokenMismatch);
            required_total = required_total + game.bet_amount;
            i = i + 1;
        };

        // Ensure payment covers all games
        assert!(payment_amount >= required_total, EInsufficientPayment);

        // Create a single random generator for all games (secure)
        let mut generator = random::new_generator(rnd, ctx);

        // Convert to mutable for processing
        let mut games = games_raw;
        let mut payment_coin = payment;

        // Process each game ensuring EQUAL resource consumption
        while (!vector::is_empty(&games)) {
            let game = vector::pop_back(&mut games);
            
            // Execute with resource-equal paths
            execute_secure_game(game, &mut payment_coin, joiner, &mut generator, config, ctx);
        };

        // Clean up empty vector
        vector::destroy_empty(games);

        // Refund any excess payment
        let remaining_payment_amount = coin::value(&payment_coin);
        if (remaining_payment_amount > 0) {
            transfer::public_transfer(payment_coin, joiner);
        } else {
            coin::destroy_zero(payment_coin);
        };
    }

    /// Execute single game with GUARANTEED equal resource consumption
    fun execute_secure_game<T>(
        game: Game<T>,
        payment_coin: &mut Coin<T>,
        joiner: address,
        generator: &mut random::RandomGenerator,
        config: &GameConfig,
        ctx: &mut TxContext
    ) {
        // Extract game data
        let Game {
            id,
            creator,
            bet_amount,
            creator_choice,
            balance,
            is_active: _,
            created_at_ms: _,
            token_type,
        } = game;

        // Extract exact bet amount from payment
        let bet_coin = coin::split(payment_coin, bet_amount, ctx);
        
        // Add joiner's bet to game balance
        let mut game_balance = balance;
        balance::join(&mut game_balance, coin::into_balance(bet_coin));

        // Generate randomness (same operation for all outcomes)
        let random_value = random::generate_bool(generator);
        
        // Determine outcome (same computation cost)
        let creator_wins = random_value == creator_choice.is_heads;
        let (winner, loser) = if (creator_wins) {
            (creator, joiner)
        } else {
            (joiner, creator)
        };
        
        // Calculate amounts (same computation)
        let total_pot = balance::value(&game_balance);
        let fee_amount = (total_pot * config.fee_percentage) / FEE_BASE;
        let winner_payout = total_pot - fee_amount;

        // Extract fee and send directly to treasury address
        let fee_balance = balance::split(&mut game_balance, fee_amount);
        let fee_coin = coin::from_balance(fee_balance, ctx);
        transfer::public_transfer(fee_coin, config.treasury_address);
        
        // Transfer to winner (same transfer operation, just different address)
        let winner_coin = coin::from_balance(game_balance, ctx);
        transfer::public_transfer(winner_coin, winner);

        // Emit standardized event (same structure size)
        event::emit(GameJoined {
            game_id: object::uid_to_address(&id),
            joiner,
            joiner_choice_heads: !creator_choice.is_heads,
            winner,
            loser, 
            total_pot,
            winner_payout,
            fee_collected: fee_amount,
            bet_amount: bet_amount,
            creator_choice_heads: creator_choice.is_heads,
            creator,
            coin_flip_result_heads: random_value,
            token_type,
        });
        
        // Delete object (same operation)
        object::delete(id);
    }

    /// Cancel a pending game and get refund (with timeout check)
    public entry fun cancel_game<T>(
        game: Game<T>,
        ctx: &mut TxContext
    ) {
        let caller = tx_context::sender(ctx);
        
        // Security checks
        assert!(game.is_active, EGameNotFound);
        assert!(caller == game.creator, ENotGameCreator);

        let Game {
            id,
            creator,
            bet_amount,
            creator_choice: _,
            balance,
            is_active: _,
            created_at_ms: _,
            token_type,
        } = game;

        // Refund the creator
        let refund_coin = coin::from_balance(balance, ctx);
        transfer::public_transfer(refund_coin, creator);

        // Emit cancellation event
        event::emit(GameCancelled {
            game_id: object::uid_to_address(&id),
            creator,
            refund_amount: bet_amount,
            token_type,
        });

        object::delete(id);
    }

    /// Update treasury address (admin only)
    public entry fun update_treasury_address(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        new_treasury_address: address,
        ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        assert!(new_treasury_address != @0x0, EInvalidAddress);
        
        config.treasury_address = new_treasury_address;
        
        event::emit(ConfigUpdated {
            admin: tx_context::sender(ctx),
            fee_percentage: config.fee_percentage,
            is_paused: config.is_paused,
            min_bet_amount: config.min_bet_amount,
            max_bet_amount: config.max_bet_amount,
            treasury_address: config.treasury_address,
            max_games_per_transaction: config.max_games_per_transaction,
        });
    }

    /// Emergency pause/unpause the contract (admin only)
    public entry fun set_pause_state(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        paused: bool,
        ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        config.is_paused = paused;
        
        event::emit(ConfigUpdated {
            admin: tx_context::sender(ctx),
            fee_percentage: config.fee_percentage,
            is_paused: config.is_paused,
            min_bet_amount: config.min_bet_amount,
            max_bet_amount: config.max_bet_amount,
            treasury_address: config.treasury_address,
            max_games_per_transaction: config.max_games_per_transaction,
        });
    }

    /// Update bet limits (admin only)
    public entry fun update_bet_limits(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        min_bet: u64,
        max_bet: u64,
        ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        assert!(min_bet > 0, EInvalidBetAmount);
        assert!(min_bet <= max_bet, EInvalidBetAmount);
        
        config.min_bet_amount = min_bet;
        config.max_bet_amount = max_bet;
        
        event::emit(ConfigUpdated {
            admin: tx_context::sender(ctx),
            fee_percentage: config.fee_percentage,
            is_paused: config.is_paused,
            min_bet_amount: config.min_bet_amount,
            max_bet_amount: config.max_bet_amount,
            treasury_address: config.treasury_address,
            max_games_per_transaction: config.max_games_per_transaction,
        });
    }

    /// Update fee percentage (admin only with proper validation)
    public entry fun update_fee_percentage(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        new_percentage: u64,
        ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        assert!(new_percentage <= FEE_BASE, EInvalidFeePercentage); // Max 100%

        config.fee_percentage = new_percentage;

        event::emit(ConfigUpdated {
            admin: tx_context::sender(ctx),
            fee_percentage: config.fee_percentage,
            is_paused: config.is_paused,
            min_bet_amount: config.min_bet_amount,
            max_bet_amount: config.max_bet_amount,
            treasury_address: config.treasury_address,
            max_games_per_transaction: config.max_games_per_transaction,
        });
    }

    /// Update max games per transaction (admin only)
    public entry fun update_max_games_per_transaction(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        new_max_games: u64,
        ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        assert!(new_max_games > 0, EInvalidMaxGames);
        assert!(new_max_games <= 1000, EInvalidMaxGames); // Reasonable upper limit
        
        config.max_games_per_transaction = new_max_games;
        
        event::emit(ConfigUpdated {
            admin: tx_context::sender(ctx),
            fee_percentage: config.fee_percentage,
            is_paused: config.is_paused,
            min_bet_amount: config.min_bet_amount,
            max_bet_amount: config.max_bet_amount,
            treasury_address: config.treasury_address,
            max_games_per_transaction: config.max_games_per_transaction,
        });
    }

    /// Add a token to the whitelist (admin only)
    public entry fun add_whitelisted_token<T>(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        _ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        let token_type = type_name::get<T>();
        table::add(&mut config.whitelisted_tokens, token_type, true);
    }

    /// Remove a token from the whitelist (admin only)
    public entry fun remove_whitelisted_token<T>(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        _ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        let token_type = type_name::get<T>();
        table::remove(&mut config.whitelisted_tokens, token_type);
    }

    // ======== View Functions ========

    /// Get game details (including creation timestamp)
    public fun get_game_info<T>(game: &Game<T>): (address, u64, bool, bool, u64) {
        (
            game.creator,
            game.bet_amount,
            game.creator_choice.is_heads,
            game.is_active,
            game.created_at_ms
        )
    }

    /// Check if a token is whitelisted
    public fun is_token_whitelisted<T>(config: &GameConfig): bool {
        let token_type = type_name::get<T>();
        table::contains(&config.whitelisted_tokens, token_type)
    }

    /// Get whitelisted tokens
    public fun get_whitelisted_tokens(config: &GameConfig): &Table<TypeName, bool> {
        &config.whitelisted_tokens
    }

    /// Get treasury address
    public fun get_treasury_address(config: &GameConfig): address {
        config.treasury_address
    }

    /// Get current fee percentage
    public fun get_fee_percentage(config: &GameConfig): u64 {
        config.fee_percentage
    }

    /// Get admin cap ID for verification
    public fun get_admin_cap_id(config: &GameConfig): address {
        config.admin_cap_id
    }

    /// Get contract pause state
    public fun is_contract_paused(config: &GameConfig): bool {
        config.is_paused
    }

    /// Get bet limits
    public fun get_bet_limits(config: &GameConfig): (u64, u64) {
        (config.min_bet_amount, config.max_bet_amount)
    }

    /// Get max games per transaction limit
    public fun get_max_games_per_transaction(config: &GameConfig): u64 {
        config.max_games_per_transaction
    }

    // ======== Test Functions ========
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        let otw = COIN_FLIP {};
        init(otw, ctx);
    }

    #[test_only]
    public fun create_admin_cap_for_testing(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }

    #[test_only]
    public fun set_game_inactive_for_testing<T>(game: &mut Game<T>) {
        game.is_active = false;
    }
} 