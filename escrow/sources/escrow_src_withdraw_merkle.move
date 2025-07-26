/// Module: escrow
module escrow::escrow_src_withdraw_merkle;

use sui::coin::{Self, Coin};
    use sui::balance;
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::hash;

    use escrow::constants::{
        error_invalid_caller,
        status_active,
        error_already_withdrawn,
        src_withdrawal,
        error_invalid_time,
        error_secret_already_used,
        error_invalid_partial_fill,
        error_invalid_merkle_proof,
        status_withdrawn,
    };
    use escrow::structs::{
        EscrowSrc,
        get_src_immutables,
        get_taker,
        get_src_status,
        get_timelocks,
        get_src_merkle_info,
        get_parts_amount,
        get_merkle_root,
        get_amount,
        get_safety_deposit,
        get_src_id,
        set_src_status,
        extract_proportional_src_balances,
        get_merkle_info_mut,
        mark_secret_used,
    };
    use escrow::events;
    use escrow::utils::{
        get_timelock_stage,
        is_secret_used,
        verify_merkle_proof,
        create_merkle_leaf,
        calculate_partial_fill_amount,
        calculate_proportional_safety_deposit,
    };

    // ============ Merkle Withdrawal Functions ============

    /// Withdraw with merkle proof for partial fills
    public fun withdraw<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        merkle_proof: vector<vector<u8>>,
        secret_index: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        withdraw_to<T>(
            escrow, 
            secret, 
            merkle_proof, 
            secret_index, 
            tx_context::sender(ctx), 
            clock, 
            ctx
        )
    }

    /// Withdraw with merkle proof to specific address
    public fun withdraw_to<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        merkle_proof: vector<vector<u8>>,
        secret_index: u64,
        target: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_src_immutables(escrow);
        let merkle_info = get_src_merkle_info(escrow);
        
        // Validate caller is taker
        assert!(
            tx_context::sender(ctx) == get_taker(immutables), 
            error_invalid_caller()
        );
        
        // Validate escrow is active
        assert!(
            get_src_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing
        let current_time = clock::timestamp_ms(clock) / 1000;
        let withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            src_withdrawal()
        );
        assert!(current_time >= withdrawal_time, error_invalid_time());

        // Validate secret index hasn't been used
        assert!(
            !is_secret_used(merkle_info, secret_index), 
            error_secret_already_used()
        );

        // Validate secret index is within bounds
        let parts_amount = get_parts_amount(merkle_info) as u64;
        assert!(
            secret_index <= parts_amount, 
            error_invalid_partial_fill()
        );

        // Validate merkle proof
        let secret_hash = hash::keccak256(&secret);
        let leaf = create_merkle_leaf(secret_index, &secret_hash);
        assert!(
            verify_merkle_proof(
                leaf, 
                &merkle_proof, 
                get_merkle_root(merkle_info)
            ),
            error_invalid_merkle_proof()
        );

        // Execute withdrawal
        execute_merkle_withdrawal(escrow, secret, secret_index, target, ctx)
    }
