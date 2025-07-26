/// Module: escrow
module escrow::escrow_dst_cancel;

use sui::coin::{Self, Coin};
    use sui::balance;
    use sui::clock::{Self, Clock};
    use sui::sui::SUI;
    use escrow::constants::{error_invalid_caller,status_active, error_already_cancelled, src_cancellation, error_invalid_time, status_cancelled};
    use escrow::structs::{Self, EscrowSrc, AccessTokengi, get_src_immutables,get_taker, get_maker, get_timelocks, set_src_status, extract_src_balances};
    use escrow::events;
    use escrow::utils;

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
        let cancellation_time = utils::get_timelock_stage(
            get_timelocks(immutables), 
            src_cancellation()
        );
        assert!(current_time >= cancellation_time, error_invalid_time());

        // Execute cancellation
        execute_cancellation(escrow, ctx)
    }

    // ============ Internal Functions ============

    /// Execute the cancellation logic
    fun execute_cancellation<T>(
        escrow: &mut EscrowSrc<T>,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_src_immutables(escrow);
        
        // Mark as cancelled
        set_src_status(escrow, status_cancelled());

        // Extract balances
        let (token_balance, sui_balance) = extract_src_balances(escrow);

        // Emit cancellation event
        events::emit_escrow_cancelled(
            structs::get_src_id(escrow),
            structs::get_maker(immutables), // Refund to maker
            sui::balance::value(&token_balance),
        );

        // Tokens go to maker, safety deposit to canceller
        transfer::public_transfer(
            sui::coin::from_balance(token_balance, ctx),
            get_maker(immutables)
        );

        // Return safety deposit to canceller
        (coin::zero<T>(ctx), coin::from_balance(sui_balance, ctx))
    }


