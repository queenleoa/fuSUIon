/// Module: escrow
module escrow::escrow_src_create;

    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use sui::sui::SUI;
    use escrow::constants::{
        error_insufficient_balance, 
        error_invalid_immutables, 
        error_invalid_secrets_amount
        };
    use escrow::structs::{EscrowImmutables};
    use escrow::structs::{
        get_amount, 
        get_safety_deposit, 
        new_merkle_info, 
        new_escrow_src,
        get_src_id, 
        get_order_hash,
        get_maker, 
        get_taker, 
        get_src_immutables, 
        get_hashlock,
        get_deployed_at,
        get_timelocks,
        };
    use escrow::events;

    // ============ Creation Function ============

    /// Create a new source escrow as a SHARED OBJECT for consensus security
    public fun create<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        merkle_root: vector<u8>,
        parts_amount: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate amounts match immutables
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
        } else {
            assert!(parts_amount == 0, error_invalid_secrets_amount());
        };

        // Create merkle info
        let merkle_info = new_merkle_info(merkle_root, parts_amount);
       
        // Create escrow
        let escrow = new_escrow_src(
            immutables,
            coin::into_balance(token_coin),
            coin::into_balance(safety_deposit),
            merkle_info,
            ctx
        );

        let escrow_id = get_src_id(&escrow);
        let order_hash = *get_order_hash(get_src_immutables(&escrow));
        let maker = get_maker(get_src_immutables(&escrow));
        let taker = get_taker(get_src_immutables(&escrow));
        let amount = get_amount(get_src_immutables(&escrow));
        let safety_deposit = get_safety_deposit(get_src_immutables(&escrow));

        // Set deployed_at timestamp in timelocks
        let timelocks = get_timelocks(get_src_immutables(&escrow));
        let current_time = sui::clock::timestamp_ms(clock) / 1000;
        let deployed_at = get_deployed_at(timelocks);

        // CRITICAL: Share the escrow object for multi-party access
        transfer::public_share_object(escrow);

        // Emit creation event
        events::emit_escrow_src_created(
            escrow_id,
            order_hash,
            maker,
            taker,
            amount,
            safety_deposit,
            is_merkle,
            parts_amount,
            deployed_at,
        );
    }
    
    // ============ Validation Functions ============

    /// Validate immutables before creation
    public fun validate_immutables(immutables: &EscrowImmutables) {
        // Validate order hash
        assert!(
            vector::length(get_order_hash(immutables)) == 32, 
            error_invalid_immutables()
        );
        
        // Validate hashlock
        assert!(
            vector::length(get_hashlock(immutables)) == 32, 
            error_invalid_immutables()
        );
        
        // Validate amounts
        assert!(
            get_amount(immutables) > 0, 
            error_invalid_immutables()
        );
        assert!(
            get_safety_deposit(immutables) > 0, 
            error_invalid_immutables()
        );
          
        // Validate addresses
        assert!(
            get_maker(immutables) != @0x0, 
            error_invalid_immutables()
        );
        assert!(
            get_taker(immutables) != @0x0, 
            error_invalid_immutables()
        );
    }