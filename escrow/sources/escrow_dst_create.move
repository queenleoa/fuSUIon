/// Module: escrow
/* module escrow::escrow_dst_create;

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use escrow::constants::{
        dst_cancellation, 
        error_invalid_creation_time,
        error_insufficient_balance, 
        error_invalid_secrets_amount,
        error_invalid_immutables
        };
    use escrow::structs::{
        EscrowImmutables, 
        get_timelocks,get_amount, 
        get_safety_deposit, 
        new_merkle_info, 
        new_escrow_dst, 
        get_order_hash, 
        get_maker, 
        get_taker,
        get_dst_id, 
        get_dst_immutables,
        get_deployed_at,
         };
    use escrow::utils::{get_timelock_stage};
    use escrow::events;
    use sui::clock::Clock;

    /// Create a new destination escrow as a SHARED OBJECT for consensus security
    public fun create<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        merkle_root: vector<u8>,
        parts_amount: u8,
        src_cancellation_timestamp: u64,
        clock: &Clock,
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

        let escrow_id = get_dst_id(&escrow);
        let order_hash = *get_order_hash(get_dst_immutables(&escrow));
        let maker = get_maker(get_dst_immutables(&escrow));
        let taker = get_taker(get_dst_immutables(&escrow));
        let amount = get_amount(get_dst_immutables(&escrow));
        let safety_deposit = get_safety_deposit(get_dst_immutables(&escrow));

        // Set deployed_at timestamp in timelocks
        let timelocks = get_timelocks(get_dst_immutables(&escrow));
        let current_time = sui::clock::timestamp_ms(clock) / 1000;

        let deployed_at = get_deployed_at(timelocks);


        // Emit creation event
        events::emit_escrow_dst_created(
           escrow_id,
            order_hash,
            maker,
            taker,
            amount,
            safety_deposit,
            src_cancellation_timestamp,
            is_merkle,
            parts_amount,
            deployed_at,
        );

        // Share the escrow object for consensus
        transfer::public_share_object(escrow);
    }

    // ============ Validation Functions ============

    /// Validate destination escrow creation parameters
    public fun validate_creation_params(
        immutables: &EscrowImmutables,
        src_cancellation_timestamp: u64,
    ): bool {
        // Check timing constraint
        let dst_cancellation_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_cancellation()
        );
        
        dst_cancellation_time <= src_cancellation_timestamp
    }

    /// Calculate required coin amounts for creation
    public fun calculate_required_amounts(
        immutables: &EscrowImmutables
    ): (u64, u64) {
        (
            get_amount(immutables),
            get_safety_deposit(immutables)
        )
    }
    */


