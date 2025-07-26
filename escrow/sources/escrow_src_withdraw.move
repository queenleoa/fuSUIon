/// Module: escrow
module escrow::escrow_src_withdraw;

    use sui::coin::{Self, Coin};
    use sui::balance;
    use sui::clock::{Self, Clock};
    use sui::sui::SUI;
    use escrow::constants::{
        error_invalid_caller,
        status_active,
        error_already_withdrawn,
        src_withdrawal,
        error_invalid_secret,
        error_invalid_time,
        status_withdrawn,
        src_public_withdrawal,
    };
    use escrow::structs::{ 
        EscrowSrc, 
        get_src_immutables,
        get_taker,
        get_src_status,
        get_timelocks,
        get_hashlock,
        get_src_id,
        set_src_status, 
        extract_src_balances,
        get_src_merkle_info,
        get_used_indices,
        get_safety_deposit,
        get_parts_amount,
        get_amount,
        };
    use escrow::events;
    use escrow::utils::{
        get_timelock_stage, 
        validate_secret,
        calculate_proportional_safety_deposit,
        calculate_partial_fill_amount,
        is_secret_used,
        };

    // ============ Simple Withdrawal Functions ============

    /// Withdraw from source escrow (private) - simple version
    public fun withdraw<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        withdraw_to<T>(escrow, secret, tx_context::sender(ctx), clock, ctx)
    }

    /// Withdraw to specific address - simple version
    public fun withdraw_to<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        target: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_src_immutables(escrow);
        
        // Validate caller is taker
        assert!(
            tx_context::sender(ctx) == get_taker(immutables), 
            error_invalid_caller()
        );
        
        // Validate escrow is active
        assert!(
            get_src_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing - must be after withdrawal time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            src_withdrawal()
        );
        assert!(current_time >= withdrawal_time, error_invalid_time());

        // Validate secret
        assert!(
            validate_secret(&secret, get_hashlock(immutables)), 
            error_invalid_secret()
        );

        // Execute withdrawal
        execute_withdrawal(escrow, secret, target, ctx)
    }

    // ============ Public Withdrawal Function ============

    /// Public withdrawal with access token
    public fun withdraw_public<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_src_immutables(escrow);
        
        // Validate escrow is active
        assert!(
            get_src_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing - must be after public withdrawal time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let public_withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            src_public_withdrawal()
        );
        assert!(current_time >= public_withdrawal_time, error_invalid_time());

        // Validate secret
        assert!(
            validate_secret(&secret, get_hashlock(immutables)), 
            error_invalid_secret()
        );

        // Execute withdrawal
        execute_withdrawal(escrow, secret, tx_context::sender(ctx), ctx)
    }

    // ============ Internal Functions ============

    /// Execute the withdrawal logic
    fun execute_withdrawal<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        recipient: address,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        // Mark as withdrawn
        set_src_status(escrow, status_withdrawn());

        // Extract balances
        let (token_balance, sui_balance) = extract_src_balances(escrow);

        // Emit withdrawal event
        events::emit_escrow_withdrawn(
            get_src_id(escrow),
            secret,
            recipient,
            balance::value(&token_balance),
            0, // No merkle index for simple withdrawal
        );

        // Convert to coins
        (coin::from_balance(token_balance, ctx), coin::from_balance(sui_balance, ctx))
    }

    // ============ View Functions ============

    /// Check if withdrawal is possible
    public fun can_withdraw<T>(
        escrow: &EscrowSrc<T>,
        clock: &Clock,
        is_public: bool
    ): bool {
        let immutables = get_src_immutables(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Check if already processed
        if (get_src_status(escrow) != status_active()) {
            return false
        };
        
        // Check timing
        let required_time = if (is_public) {
            get_timelock_stage(
                get_timelocks(immutables), 
                src_public_withdrawal()
            )
        } else {
            get_timelock_stage(
                get_timelocks(immutables), 
                src_withdrawal()
            )
        };
        
        current_time >= required_time
    }

    /// Get time until withdrawal is possible
    public fun time_until_withdrawal<T>(
        escrow: &EscrowSrc<T>,
        clock: &Clock,
        is_public: bool
    ): u64 {
        let immutables = get_src_immutables(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        let required_time = if (is_public) {
            get_timelock_stage(
                get_timelocks(immutables), 
                src_public_withdrawal()
            )
        } else {
            get_timelock_stage(
                get_timelocks(immutables), 
                src_withdrawal()
            )
        };
        
        if (current_time >= required_time) {
            0
        } else {
            required_time - current_time
        }
    }

    /// Get the recipient of tokens upon withdrawal
    public fun get_withdrawal_recipient<T>(escrow: &EscrowSrc<T>): address {
        get_taker(get_src_immutables(escrow))
    }
