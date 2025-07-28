/// Module: escrow
/*module escrow::escrow_src_cancel;

    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::sui::SUI;
    use escrow::constants::{error_invalid_caller,status_active, error_already_cancelled, src_cancellation, error_invalid_time, status_cancelled, src_public_cancellation};
    use escrow::structs::{Self, EscrowSrc, get_src_immutables,get_taker, get_maker, get_timelocks, set_src_status, extract_src_balances, get_src_status, get_src_id};
    use escrow::utils::{get_timelock_stage};
    use escrow::events;

// ============ Private Cancellation ============

    /// Cancel source escrow (private) - only taker can call
    public fun cancel<T>(
        escrow: &mut EscrowSrc<T>,
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
            structs::get_src_status(escrow) == status_active(), 
            error_already_cancelled()
        );
        
        // Validate timing - must be after cancellation time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let cancellation_time = get_timelock_stage(
            get_timelocks(immutables), 
            src_cancellation()
        );
        assert!(current_time >= cancellation_time, error_invalid_time());

        // Execute cancellation
        execute_cancellation(escrow, ctx)
    }

    // ============ Public Cancellation ============

    /// Public cancellation with access token
    public fun cancel_public<T>(
        escrow: &mut EscrowSrc<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_src_immutables(escrow);
        
        // Validate escrow is active
        assert!(
            get_src_status(escrow) == status_active(), 
            error_already_cancelled()
        );
        
        // Validate timing - must be after public cancellation time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let public_cancellation_time = get_timelock_stage(
            get_timelocks(immutables), 
            src_public_cancellation()
        );
        assert!(current_time >= public_cancellation_time, error_invalid_time());

        // Execute cancellation
        execute_cancellation(escrow, ctx)
    }

    // ============ Internal Functions ============

    /// Execute the cancellation logic
    fun execute_cancellation<T>(
        escrow: &mut EscrowSrc<T>,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        // ── 1- Grab data we’ll still need after mutation ─────────────── 
        let maker      = get_maker(get_src_immutables(escrow));
        let src_id     = get_src_id(escrow);

    // ── 2- Mutate escrow (requires &mut) ─────────────────────────── 
        set_src_status(escrow, status_cancelled());

        let (token_balance, sui_balance) = extract_src_balances(escrow);

    // ── 3- Emit event (immutable borrow is allowed again; the prior
           &mut borrow ended when `extract_src_balances` returned) ─── 
        events::emit_escrow_cancelled(
            src_id,
            maker,
            sui::balance::value(&token_balance),
        );

        // Tokens go to maker, safety deposit to canceller
        transfer::public_transfer(
            sui::coin::from_balance(token_balance, ctx),
            maker
        );

        // Return safety deposit to canceller
        (coin::zero<T>(ctx), coin::from_balance(sui_balance, ctx))
    }

    // ============ View Functions ============

    /// Check if escrow can be cancelled
    public fun can_cancel<T>(
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
                src_public_cancellation()
            )
        } else {
                get_timelock_stage(
                get_timelocks(immutables), 
                src_cancellation()
            )
        };
        
        current_time >= required_time
    }



