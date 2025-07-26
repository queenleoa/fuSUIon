/// Module: escrow
module escrow::escrow_src_create;

    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use escrow::constants;
    use escrow::structs::{EscrowImmutables};
    use escrow::structs::{get_amount, get_safety_deposit, new_merkle_info, new_escrow_src,get_src_id, get_order_hash,get_maker, get_taker, get_src_immutables, get_hashlock};
    use escrow::events;

    // ============ Creation Functions ============

    /// Create a new source escrow as a SHARED OBJECT for consensus security
    public fun create<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        create_with_merkle<T>(
            immutables,
            token_coin,
            safety_deposit,
            vector::empty(), // No merkle root for simple escrow
            0, // No parts for simple escrow
            ctx
        )
    }

    /// Create a new source escrow with merkle tree support for partial fills
    public fun create_with_merkle<T>(
        immutables: EscrowImmutables,
        token_coin: Coin<T>,
        safety_deposit: Coin<SUI>,
        merkle_root: vector<u8>,
        parts_amount: u8,
        ctx: &mut TxContext
    ) {
        // Validate amounts match immutables
        assert!(
            coin::value(&token_coin) == get_amount(&immutables), 
            constants::error_insufficient_balance()
        );
        assert!(
            coin::value(&safety_deposit) == get_safety_deposit(&immutables), 
            constants::error_insufficient_balance()
        );

        // Validate merkle configuration
        let is_merkle = vector::length(&merkle_root) > 0;
        if (is_merkle) {
            assert!(parts_amount > 0, constants::error_invalid_secrets_amount());
            assert!(vector::length(&merkle_root) == 32, constants::error_invalid_immutables());
        };

        // Create merkle info
        let merkle_info = if (is_merkle) {
            new_merkle_info(merkle_root, parts_amount)
        } else {
            new_merkle_info(vector::empty(), 0)
        };

        // Create escrow
        let escrow = new_escrow_src<T>(
            immutables,
            coin::into_balance(token_coin),
            coin::into_balance(safety_deposit),
            merkle_info,
            ctx
        );

        // Emit creation event
        events::emit_escrow_src_created(
            get_src_id(&escrow),
            *get_order_hash(get_src_immutables(&escrow)),
            get_maker(get_src_immutables(&escrow)),
            get_taker(get_src_immutables(&escrow)),
            get_amount(get_src_immutables(&escrow)),
            get_safety_deposit(get_src_immutables(&escrow)),
            is_merkle,
            parts_amount,
        );

        // Share the escrow object for consensus
        transfer::public_share_object(escrow);
    }
    
    // ============ Validation Functions ============

    /// Validate immutables before creation
    public fun validate_immutables(immutables: &EscrowImmutables) {
        // Validate order hash
        assert!(
            vector::length(get_order_hash(immutables)) == 32, 
            constants::error_invalid_immutables()
        );
        
        // Validate hashlock
        assert!(
            vector::length(get_hashlock(immutables)) == 32, 
            constants::error_invalid_immutables()
        );
        
        // Validate amounts
        assert!(
            get_amount(immutables) > 0, 
            constants::error_invalid_immutables()
        );
        assert!(
            get_safety_deposit(immutables) > 0, 
            constants::error_invalid_immutables()
        );
        
        // Validate addresses
        assert!(
            get_maker(immutables) != @0x0, 
            constants::error_invalid_immutables()
        );
        assert!(
            get_taker(immutables) != @0x0, 
            constants::error_invalid_immutables()
        );
    }