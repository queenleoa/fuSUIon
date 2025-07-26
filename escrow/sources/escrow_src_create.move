/// Module: escrow
module escrow::escrow_src_create;

    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::sui::SUI;

    use escrow::constants;
    use escrow::structs::EscrowImmutables;
    use escrow::events;

    // ============ Creation Functions ============

    /// Create a new source escrow as a SHARED OBJECT for consensus security
    public fun create<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        create_with_merkle<T>(
            immutables,
            token_coin,
            safety_deposit,
            vector::empty(), // No merkle root for simple escrow
            0, // No parts for simple escrow
            clock,
            ctx
        )
    }

    