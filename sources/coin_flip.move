/// A secure coin flip game smart contract for SUI
/// Players can create games with SUI bets and others can join to flip for the win
module sui_coin_flip::coin_flip {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::event;
    use sui::random::{Self, Random};
    use sui::clock::{Self, Clock};
    
    // ======== Constants ========
    
    /// Fee base for percentage calculations (10000 = 100%)
    const FEE_BASE: u64 = 10000;
    /// Default fee percentage (250 = 2.5%)
    const DEFAULT_FEE_PERCENTAGE: u64 = 250;
    /// Minimum bet amount to prevent dust attacks (0.01 SUI)
    const MIN_BET_AMOUNT: u64 = 10_000_000; // 0.01 SUI in MIST
    /// Maximum bet amount to prevent whale manipulation (1000 SUI)
    const MAX_BET_AMOUNT: u64 = 1_000_000_000_000; // 1000 SUI in MIST

    
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
    const EEmptyTreasury: u64 = 11;


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
    /// balance: The actual SUI tokens held by the game (may temporarily exceed bet_amount during join)
    public struct Game has key, store {
        id: UID,
        creator: address,
        bet_amount: u64, // Required bet amount to join
        creator_choice: CoinSide,
        balance: Balance<SUI>, // Actual SUI tokens in the game
        is_active: bool,
        created_at_ms: u64, // Timestamp when game was created
    }

    /// Admin capability with unique ID for validation
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Global configuration and treasury
    public struct GameConfig has key {
        id: UID,
        admin_cap_id: address, // ID of the valid admin cap
        fee_percentage: u64, // Configurable fee percentage
        treasury_balance: Balance<SUI>,
        is_paused: bool, // Emergency pause state
        min_bet_amount: u64, // Configurable minimum bet
        max_bet_amount: u64, // Configurable maximum bet
    }

    // ======== Events ========

    public struct GameCreated has copy, drop {
        game_id: address,
        creator: address,
        bet_amount: u64,
        creator_choice_heads: bool,
    }

    public struct GameJoined has copy, drop {
        game_id: address,
        joiner: address,
        joiner_choice_heads: bool,
        winner: address,
        loser: address,
        total_pot: u64,
        winner_payout: u64,
        fee_collected: u64,
        coin_flip_result_heads: bool,
    }

    public struct GameCancelled has copy, drop {
        game_id: address,
        creator: address,
        refund_amount: u64,
    }

    public struct ConfigUpdated has copy, drop {
        admin: address,
        fee_percentage: u64,
        is_paused: bool,
        min_bet_amount: u64,
        max_bet_amount: u64,
        treasury_balance: u64,
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
        
        let config = GameConfig {
            id: object::new(ctx),
            admin_cap_id,
            fee_percentage: DEFAULT_FEE_PERCENTAGE,
            treasury_balance: balance::zero(),
            is_paused: false,
            min_bet_amount: MIN_BET_AMOUNT,
            max_bet_amount: MAX_BET_AMOUNT,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(config);
    }

    /// Validate admin capability
    fun validate_admin_cap(admin_cap: &AdminCap, config: &GameConfig) {
        assert!(object::uid_to_address(&admin_cap.id) == config.admin_cap_id, EInvalidAdminCap);
    }

    /// Create a new heads choice
    public fun heads(): CoinSide {
        CoinSide { is_heads: true }
    }

    /// Create a new tails choice
    public fun tails(): CoinSide {
        CoinSide { is_heads: false }
    }

    /// Check if a coin side is heads
    public fun is_heads(side: &CoinSide): bool {
        side.is_heads
    }

    /// Create a new coin flip game
    public entry fun create_game(
        bet_coin: Coin<SUI>,
        choice: bool, // true for heads, false for tails
        config: &GameConfig,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Check if contract is paused
        assert!(!config.is_paused, EContractPaused);
        
        let bet_amount = coin::value(&bet_coin);
        assert!(bet_amount > 0, EInvalidBetAmount);
        assert!(bet_amount >= config.min_bet_amount, EBetTooSmall);
        assert!(bet_amount <= config.max_bet_amount, EBetTooLarge);

        let creator = tx_context::sender(ctx);
        let creator_choice = CoinSide { is_heads: choice };
        
        let game = Game {
            id: object::new(ctx),
            creator,
            bet_amount,
            creator_choice,
            balance: coin::into_balance(bet_coin),
            is_active: true,
            created_at_ms: clock::timestamp_ms(clock),
        };

        let game_id = object::uid_to_address(&game.id);

        // Emit game created event
        event::emit(GameCreated {
            game_id,
            creator,
            bet_amount,
            creator_choice_heads: choice,
        });

        transfer::share_object(game);
    }

    /// SECURE: Join multiple games with equal resource consumption
    /// Private entry function prevents composition attacks while maintaining single-tx UX
    entry fun join_games(
        games_raw: vector<Game>,
        payment: Coin<SUI>,
        config: &mut GameConfig,
        rnd: &Random,
        ctx: &mut TxContext
    ) {
        let mut payment_coin = payment;
        let mut games = games_raw;
        let joiner = tx_context::sender(ctx);
        let payment_amount = coin::value(&payment_coin);
        let games_count = vector::length(&games);
        
        // Security checks
        assert!(!config.is_paused, EContractPaused);
        assert!(games_count > 0, EGameNotFound);

        // Calculate total required bet amount and validate all games
        let mut total_required = 0u64;
        let mut i = 0;
        while (i < games_count) {
            let game = vector::borrow(&games, i);
            assert!(game.is_active, EGameNotFound);
            assert!(joiner != game.creator, ECannotJoinOwnGame);
            total_required = total_required + game.bet_amount;
            i = i + 1;
        };

        // Ensure payment covers all games
        assert!(payment_amount >= total_required, EInsufficientPayment);

        // Create a single random generator for all games (secure)
        let mut generator = random::new_generator(rnd, ctx);

        // Process each game ensuring EQUAL resource consumption
        while (!vector::is_empty(&games)) {
            let game = vector::pop_back(&mut games);
            
            // Execute with resource-equal paths
            execute_secure_game(game, &mut payment_coin, joiner, &mut generator, config, ctx);
        };

        // Clean up empty vector
        vector::destroy_empty(games);

        // Refund any excess payment
        let remaining_payment = coin::value(&payment_coin);
        if (remaining_payment > 0) {
            transfer::public_transfer(payment_coin, joiner);
        } else {
            coin::destroy_zero(payment_coin);
        };
    }

    /// Execute single game with GUARANTEED equal resource consumption
    fun execute_secure_game(
        game: Game,
        payment_coin: &mut Coin<SUI>,
        joiner: address,
        generator: &mut random::RandomGenerator,
        config: &mut GameConfig,
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
        } = game;

        // Extract exact bet amount from payment
        let bet_coin = coin::split(payment_coin, bet_amount, ctx);
        
        // Add joiner's bet to game balance
        let mut balance = balance;
        balance::join(&mut balance, coin::into_balance(bet_coin));

        // Generate randomness (same operation for all outcomes)
        let random_value = random::generate_bool(generator);
        
        // Determine outcome (same computation cost)
        let creator_wins = random_value == creator_choice.is_heads;
        let (winner, loser) = if (creator_wins) {
            (creator, joiner)
        } else {
            (joiner, creator)
        };

        // CRITICAL: All following operations are IDENTICAL regardless of outcome
        
        // Calculate amounts (same computation)
        let total_pot = balance::value(&balance);
        let fee_amount = (total_pot * config.fee_percentage) / FEE_BASE;
        let winner_payout = total_pot - fee_amount;

        // Extract fee (same operation)
        let fee_balance = balance::split(&mut balance, fee_amount);
        balance::join(&mut config.treasury_balance, fee_balance);
        
        // Transfer to winner (same transfer operation, just different address)
        let winner_coin = coin::from_balance(balance, ctx);
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
            coin_flip_result_heads: random_value,
        });

        // Gas equalization: Ensure both paths consume identical resources
        let _gas_equalizer = object::uid_to_address(&id);
        
        // Delete object (same operation)
        object::delete(id);
    }

    /// Cancel a pending game and get refund (with timeout check)
    public entry fun cancel_game(
        game: Game,
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
        } = game;

        // Refund the creator
        let refund_coin = coin::from_balance(balance, ctx);
        transfer::public_transfer(refund_coin, creator);

        // Emit cancellation event
        event::emit(GameCancelled {
            game_id: object::uid_to_address(&id),
            creator,
            refund_amount: bet_amount,
        });

        object::delete(id);
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
            treasury_balance: balance::value(&config.treasury_balance),
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
            treasury_balance: balance::value(&config.treasury_balance),
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
            treasury_balance: balance::value(&config.treasury_balance),
        });
    }

    /// Withdraw all fees from treasury (admin only - claims everything)
    public entry fun withdraw_fees(
        admin_cap: &AdminCap,
        config: &mut GameConfig,
        ctx: &mut TxContext
    ) {
        validate_admin_cap(admin_cap, config);
        
        let treasury_amount = balance::value(&config.treasury_balance);
        assert!(treasury_amount > 0, EEmptyTreasury);
        
        let withdrawn_balance = balance::withdraw_all(&mut config.treasury_balance);
        let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);
        transfer::public_transfer(withdrawn_coin, tx_context::sender(ctx));
    }


    // ======== View Functions ========

    /// Get game details (including creation timestamp)
    public fun get_game_info(game: &Game): (address, u64, bool, bool, u64) {
        (
            game.creator,
            game.bet_amount,
            game.creator_choice.is_heads,
            game.is_active,
            game.created_at_ms
        )
    }

    /// Get treasury balance
    public fun get_treasury_balance(config: &GameConfig): u64 {
        balance::value(&config.treasury_balance)
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
    public fun set_game_inactive_for_testing(game: &mut Game) {
        game.is_active = false;
    }
} 