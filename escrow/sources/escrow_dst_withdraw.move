/// Module: escrow
/*module escrow::escrow_dst_withdraw;

    use sui::coin::{Self, Coin};
    use sui::balance;
    use sui::clock::{Self, Clock};
    use sui::sui::SUI;
    use escrow::constants::{
        error_invalid_caller,
        status_active,
        error_already_withdrawn,
        dst_withdrawal,
        error_invalid_secret,
        error_invalid_time,
        status_withdrawn,
        dst_public_withdrawal,
    };
    use escrow::structs::{
        EscrowDst,
        get_dst_immutables,
        get_taker,
        get_maker,
        get_dst_status,
        get_timelocks,
        get_hashlock,
        get_dst_id,
        set_dst_status, 
        extract_dst_balances
        };
    use escrow::events;
    use escrow::utils::{get_timelock_stage, validate_secret};

    // ============ Private Withdrawal ============

    /// Withdraw from destination escrow (private) - only taker can call
    public fun withdraw<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_dst_immutables(escrow);
        
        // Validate caller is taker
        assert!(
            tx_context::sender(ctx) == get_taker(immutables), 
            error_invalid_caller()
        );
        
        // Validate escrow is active
        assert!(
            get_dst_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing - must be after withdrawal time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_withdrawal()
        );
        assert!(current_time >= withdrawal_time, error_invalid_time());

        // Validate secret
        assert!(
            validate_secret(&secret, get_hashlock(immutables)), 
            error_invalid_secret()
        );

        // Execute withdrawal
        execute_withdrawal(escrow, secret, ctx)
    }

    // ============ Public Withdrawal ============

    /// Public withdrawal with access token
    public fun withdraw_public<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_dst_immutables(escrow);
        
        // Validate escrow is active
        assert!(
            get_dst_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing - must be after public withdrawal time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let public_withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_public_withdrawal()
        );
        assert!(current_time >= public_withdrawal_time, error_invalid_time());

        // Validate secret
        assert!(
            validate_secret(&secret, get_hashlock(immutables)), 
            error_invalid_secret()
        );

        // Execute withdrawal
        execute_withdrawal(escrow, secret, ctx)
    }

    // ============ Internal Functions ============

    /// Execute the withdrawal logic
    fun execute_withdrawal<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_dst_immutables(escrow);
        let maker = get_maker(immutables);
        
        // Mark as withdrawn
        set_dst_status(escrow, status_withdrawn());

        // Extract balances
        let (token_balance, sui_balance) = extract_dst_balances(escrow);

        // Emit withdrawal event
        events::emit_escrow_withdrawn(
            get_dst_id(escrow),
            secret,
            maker, // Tokens go to maker on dst chain
            balance::value(&token_balance),
            0,
        );

        // Transfer tokens to maker
        transfer::public_transfer(
            coin::from_balance(token_balance, ctx),
            maker
        );

        // Return safety deposit to withdrawer
        (coin::zero<T>(ctx), coin::from_balance(sui_balance, ctx))
    }

    // ============ View Functions ============

    /// Check if withdrawal is possible
    public fun can_withdraw<T>(
        escrow: &EscrowDst<T>,
        clock: &Clock,
        is_public: bool
    ): bool {
        let immutables = get_dst_immutables(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Check if already processed
        if (get_dst_status(escrow) != status_active()) {
            return false
        };
        
        // Check timing
        let required_time = if (is_public) {
            get_timelock_stage(
                get_timelocks(immutables), 
                dst_public_withdrawal()
            )
        } else {
            get_timelock_stage(
                get_timelocks(immutables), 
                dst_withdrawal()
            )
        };
        
        current_time >= required_time
    }

    /// Get time until withdrawal is possible
    public fun time_until_withdrawal<T>(
        escrow: &EscrowDst<T>,
        clock: &Clock,
        is_public: bool
    ): u64 {
        let immutables = get_dst_immutables(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        let required_time = if (is_public) {
            get_timelock_stage(
                get_timelocks(immutables), 
                dst_public_withdrawal()
            )
        } else {
            get_timelock_stage(
                get_timelocks(immutables), 
                dst_withdrawal()
            )
        };
        
        if (current_time >= required_time) {
            0
        } else {
            required_time - current_time
        }
    }

    /// Get the recipient of tokens upon withdrawal
    public fun get_withdrawal_recipient<T>(escrow: &EscrowDst<T>): address {
        get_maker(get_dst_immutables(escrow))
    }