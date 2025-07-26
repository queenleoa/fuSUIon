/// Module: escrow
module escrow::escrow_dst_create;

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use escrow::constants::{dst_cancellation, error_invalid_creation_time,error_insufficient_balance, error_invalid_secrets_amount,error_invalid_immutables};
    use escrow::structs::{EscrowImmutables, get_timelocks,get_amount, get_safety_deposit, new_merkle_info, new_escrow_dst, get_order_hash, get_maker, get_taker,get_dst_id, get_dst_immutables };
    use escrow::utils::{get_timelock_stage};
    use escrow::events;

    /// Create a new destination escrow as a SHARED OBJECT for consensus security
    public fun create<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        src_cancellation_timestamp: u64,
        ctx: &mut TxContext
    ) {
        create_with_merkle<T>(
            immutables,
            token_coin,
            safety_deposit,
            vector::empty(), // No merkle root for simple escrow
            0, // No parts for simple escrow
            src_cancellation_timestamp,
            ctx
        )
    }

    /// Create a new destination escrow with merkle tree support for partial fills
    public fun create_with_merkle<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        merkle_root: vector<u8>,
        parts_amount: u8,
        src_cancellation_timestamp: u64,
        ctx: &mut TxContext
    ) {
        // Validate deployment timing - dst cancellation must not be later than src cancellation
        let dst_cancellation_time = get_timelock_stage(
            get_timelocks(&immutables), 
            dst_cancellation()
        );
        
        assert!(
            dst_cancellation_time <= src_cancellation_timestamp, 
            error_invalid_creation_time()
        );

        // Verify amounts match immutables
        assert!(
            coin::value(&token_coin) == get_amount(&immutables), 
            error_insufficient_balance()
        );
        assert!(
            coin::value(&safety_deposit) == get_safety_deposit(&immutables), 
            error_insufficient_balance()
        );

        // Validate merkle configuration
        let is_merkle = vector::length(&merkle_root) > 0;
        if (is_merkle) {
            assert!(parts_amount > 0, error_invalid_secrets_amount());
            assert!(vector::length(&merkle_root) == 32, error_invalid_immutables());
        };

        // Create merkle info
        let merkle_info = if (is_merkle) {
            new_merkle_info(merkle_root, parts_amount)
        } else {
            new_merkle_info(vector::empty(), 0)
        };

        // Create escrow
        let escrow = new_escrow_dst<T>(
            immutables,
            coin::into_balance(token_coin),
            coin::into_balance(safety_deposit),
            merkle_info,
            ctx
        );

        // Emit creation event
        events::emit_escrow_dst_created(
            get_dst_id(&escrow),
            *get_order_hash(get_dst_immutables(&escrow)),
            get_maker(get_dst_immutables(&escrow)),
            get_taker(get_dst_immutables(&escrow)),
            get_amount(get_dst_immutables(&escrow)),
            get_safety_deposit(get_dst_immutables(&escrow)),
            src_cancellation_timestamp,
            is_merkle,
            parts_amount,
        );

        // Share the escrow object for consensus
        transfer::public_share_object(escrow);
    }

