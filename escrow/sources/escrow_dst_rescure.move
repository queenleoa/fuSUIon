/// Module: escrow
module escrow::escrow_dst_rescue;

use sui::coin::{Self, Coin};
    use sui::balance;
    use sui::clock::{Self, Clock};
    use sui::sui::SUI;
    use escrow::constants::{
        status_active,
        error_already_withdrawn,
        error_invalid_time,
    };
    use escrow::structs::{
        EscrowDst,
        get_dst_immutables,
        get_dst_status,
        get_timelocks,
        get_deployed_at,
        get_dst_id,
        extract_dst_balances,
        dst_sui_balance_value,
        dst_token_balance_value,
        };
    use escrow::events;

    // ============ Rescue Function ============

    /// Rescue funds after extended period
    public fun rescue<T>(
        escrow: &mut EscrowDst<T>,
        rescue_delay: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        // Validate escrow can be rescued
        validate_rescue(escrow, rescue_delay, clock);
        
        // Execute rescue
        execute_rescue(escrow, ctx)
    }

    // ============ Internal Functions ============

    /// Validate rescue conditions
    fun validate_rescue<T>(
        escrow: &EscrowDst<T>,
        rescue_delay: u64,
        clock: &Clock
    ) {
        // Can only rescue if not already processed
        assert!(
            get_dst_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing - must be after rescue time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let immutables = get_dst_immutables(escrow);
        let deployed_at = get_deployed_at(get_timelocks(immutables));
        let rescue_time = deployed_at + rescue_delay;
        
        assert!(current_time >= rescue_time, error_invalid_time());
    }

    /// Execute the rescue logic
    fun execute_rescue<T>(
        escrow: &mut EscrowDst<T>,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        // Extract all remaining balances
        let (token_balance, sui_balance) = extract_dst_balances(escrow);

        // Emit rescue event
        events::emit_funds_rescued(
            get_dst_id(escrow),
            tx_context::sender(ctx),
            balance::value(&token_balance),
            balance::value(&sui_balance),
        );

        // Convert to coins and return to rescuer
        (coin::from_balance(token_balance, ctx), coin::from_balance(sui_balance, ctx))
    }

    // ============ View Functions ============

    /// Check if escrow can be rescued
    public fun can_rescue<T>(
        escrow: &EscrowDst<T>,
        rescue_delay: u64,
        clock: &Clock
    ): bool {
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Check if already processed
        if (get_dst_status(escrow) != status_active()) {
            return false
        };
        
        // Check timing
        let immutables = get_dst_immutables(escrow);
        let deployed_at = get_deployed_at(get_timelocks(immutables));
        let rescue_time = deployed_at + rescue_delay;
        
        current_time >= rescue_time
    }

    /// Get time until rescue is possible
    public fun time_until_rescue<T>(
        escrow: &EscrowDst<T>,
        rescue_delay: u64,
        clock: &Clock
    ): u64 {
        let current_time = clock::timestamp_ms(clock) / 1000;
        let immutables = get_dst_immutables(escrow);
        let deployed_at = get_deployed_at(get_timelocks(immutables));
        let rescue_time = deployed_at + rescue_delay;
        
        if (current_time >= rescue_time) {
            0
        } else {
            rescue_time - current_time
        }
    }

    /// Get the total rescueable amounts
    public fun get_rescueable_amounts<T>(escrow: &EscrowDst<T>): (u64, u64) {
        (
           dst_token_balance_value(escrow),
            dst_sui_balance_value(escrow)
        )
    }

    /// Get rescue timestamp
    public fun get_rescue_timestamp<T>(
        escrow: &EscrowDst<T>,
        rescue_delay: u64
    ): u64 {
        let immutables = get_dst_immutables(escrow);
        let deployed_at = get_deployed_at(get_timelocks(immutables));
        deployed_at + rescue_delay
    }
