/// Module: escrow
module escrow::escrow_dst_create;

    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::tx_context::TxContext;
    use sui::sui::SUI;

    use escrow::constants;
    use escrow::structs::{Self, EscrowImmutables};
    use escrow::events;
    use escrow::utils;

    /// Create a new destination escrow as a SHARED OBJECT for consensus security
    public fun create<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        src_cancellation_timestamp: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        create_with_merkle<T>(
            immutables,
            token_coin,
            safety_deposit,
            vector::empty(), // No merkle root for simple escrow
            0, // No parts for simple escrow
            src_cancellation_timestamp,
            clock,
            ctx
        )
    }
