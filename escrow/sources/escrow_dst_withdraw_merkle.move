/// Module: escrow
module escrow::escrow_dst_withdraw_merkle;

use sui::coin::{Self, Coin};
    use sui::balance;
    use sui::clock::{Self, Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::sui::SUI;
    use sui::hash;

    use escrow::constants::{
        error_invalid_caller,
        status_active,
        error_already_withdrawn,
        dst_withdrawal,
        dst_public_withdrawal,
        error_invalid_time,
        error_secret_already_used,
        error_invalid_partial_fill,
        error_invalid_merkle_proof,
        status_withdrawn,
    };
    use escrow::structs::{
        EscrowDst,
        AccessToken,
        get_dst_immutables,
        get_taker,
        get_maker,
        get_dst_status,
        get_timelocks,
        get_dst_merkle_info,
        get_parts_amount,
        get_merkle_root,
        get_amount,
        get_safety_deposit,
        get_dst_id,
        get_used_indices,
        set_dst_status,
        extract_proportional_dst_balances,
        get_dst_merkle_info_mut,
        mark_secret_used,
        get_dst_merkle_info,

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
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        merkle_proof: vector<vector<u8>>,
        secret_index: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_dst_immutables(escrow);
        let merkle_info = get_dst_merkle_info(escrow);
        
        // Validate caller is taker
        assert!(
            tx_context::sender(ctx) == get_taker(immutables), 
            error_invalid_caller()
        );
        
        // Validate escrow is active
        assert!(
            get_dst_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing
        let current_time = clock::timestamp_ms(clock) / 1000;
        let withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_withdrawal()
        );
        assert!(current_time >= withdrawal_time, error_invalid_time());

        // Validate merkle parameters
        validate_merkle_withdrawal(escrow, &secret, &merkle_proof, secret_index);

        // Execute withdrawal
        execute_merkle_withdrawal(escrow, secret, secret_index, ctx)
    }

    /// Public withdrawal with merkle proof and access token
    public fun withdraw_public<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        merkle_proof: vector<vector<u8>>,
        secret_index: u64,
        access_token: &AccessToken,
        clock: &Clock,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_dst_immutables(escrow);
        
        // Validate escrow is active
        assert!(
            get_dst_status(escrow) == status_active(), 
            error_already_withdrawn()
        );
        
        // Validate timing - must be after public withdrawal time
        let current_time = clock::timestamp_ms(clock) / 1000;
        let public_withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            dst_public_withdrawal()
        );
        assert!(current_time >= public_withdrawal_time, error_invalid_time());

        // Validate merkle parameters
        validate_merkle_withdrawal(escrow, &secret, &merkle_proof, secret_index);

        // Execute withdrawal
        execute_merkle_withdrawal(escrow, secret, secret_index, ctx)
    }
