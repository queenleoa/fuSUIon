/// Module: escrow
module escrow::escrow_dst_cancel;

use sui::coin::{Self, Coin};
    use sui::balance;
    use sui::clock::{Self, Clock};
    use sui::sui::SUI;
    use escrow::constants::{status_active, error_already_cancelled, dst_cancellation, status_cancelled, error_invalid_time};
    use escrow::structs::{EscrowDst, get_dst_immutables, get_dst_status, get_timelocks, set_dst_status, extract_dst_balances, get_taker, get_dst_id};
    use escrow::events;
    use escrow::utils::{get_timelock_stage};


    // ============ Cancellation Function ============

    /// Cancel destination escrow (refund to taker)
    /// Anyone can call this after cancellation time to claim the safety deposit
    public fun cancel<T>(
        escrow: &mut EscrowDst<T>,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_dst_immutables(escrow);
        
        // Validate escrow is active
        assert!(
            get_dst_status(escrow) == status_active(), 
            error_already_cancelled()
        );
        
        // Validate timing - must be after cancellation time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let cancellation_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_cancellation()
        );
        assert!(current_time >= cancellation_time, error_invalid_time());

        /* ── 1- Grab data we'll still need after mutation ─────────────── */
        let taker = get_taker(immutables);
        let dst_id = get_dst_id(escrow);

        /* ── 2- Mutate escrow (requires &mut) ─────────────────────────── */
        set_dst_status(escrow, status_cancelled());

        let (token_balance, sui_balance) = extract_dst_balances(escrow);

        /* ── 3- Emit event (immutable borrow is allowed again) ────────── */
        events::emit_escrow_cancelled(
            dst_id,
            taker, // Refund to taker
            balance::value(&token_balance),
        );

        // Refund tokens to taker
        transfer::public_transfer(
            coin::from_balance(token_balance, ctx),
            taker
        );

        // Safety deposit goes to canceller as incentive
        (coin::zero<T>(ctx), coin::from_balance(sui_balance, ctx))
    }

    // ============ View Functions ============

    /// Check if escrow can be cancelled
    public fun can_cancel<T>(
        escrow: &EscrowDst<T>,
        clock: &Clock
    ): bool {
        let immutables = get_dst_immutables(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Check if already processed
        if (get_dst_status(escrow) != status_active()) {
            return false
        };
        
        // Check timing
        let cancellation_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_cancellation()
        );
        
        current_time >= cancellation_time
    }

    /// Get time until cancellation is possible
    public fun time_until_cancellation<T>(
        escrow: &EscrowDst<T>,
        clock: &Clock
    ): u64 {
        let immutables = get_dst_immutables(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        let cancellation_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_cancellation()
        );
        
        if (current_time >= cancellation_time) {
            0
        } else {
            cancellation_time - current_time
        }
    }

    /// Get the recipient of refunded tokens if cancelled
    public fun get_refund_recipient<T>(escrow: &EscrowDst<T>): address {
        get_taker(get_dst_immutables(escrow))
    }
}