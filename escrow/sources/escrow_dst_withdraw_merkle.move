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

    // ============ Internal Functions ============

    /// Validate merkle withdrawal parameters
    fun validate_merkle_withdrawal<T>(
        escrow: &EscrowDst<T>,
        secret: &vector<u8>,
        merkle_proof: &vector<vector<u8>>,
        secret_index: u64
    ) {
        let merkle_info = get_dst_merkle_info(escrow);
        
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
        let secret_hash = hash::keccak256(secret);
        let leaf = create_merkle_leaf(secret_index, &secret_hash);
        assert!(
            verify_merkle_proof(
                leaf, 
                merkle_proof, 
                get_merkle_root(merkle_info)
            ),
            error_invalid_merkle_proof()
        );
    }

    /// Execute the merkle withdrawal logic
    fun execute_merkle_withdrawal<T>(
        escrow: &mut EscrowDst<T>,
        secret: vector<u8>,
        secret_index: u64,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        let immutables = get_dst_immutables(escrow);
        let merkle_info = get_dst_merkle_info(escrow);
        let maker = get_maker(immutables);
        
        // Mark secret as used
        mark_secret_used(get_dst_merkle_info_mut(escrow), secret_index);

        // Calculate fill amount
        let total_amount = get_amount(immutables);
        let parts_amount = get_parts_amount(merkle_info) as u64;
        let fill_amount = calculate_partial_fill_amount(
            total_amount, 
            parts_amount, 
            secret_index
        );
        let sui_amount = calculate_proportional_safety_deposit(
            get_safety_deposit(immutables),
            fill_amount,
            total_amount
        );

        // Extract proportional balances
        let (token_balance, sui_balance) = extract_proportional_dst_balances(
            escrow, 
            fill_amount, 
            sui_amount
        );

        // Check if fully withdrawn
        if (balance::value(&escrow.token_balance) == 0) {
            set_dst_status(escrow, status_withdrawn());
        };

        // Emit withdrawal event
        events::emit_escrow_withdrawn(
            get_dst_id(escrow),
            secret,
            maker, // Tokens go to maker
            fill_amount,
            secret_index,
        );

        // Transfer tokens to maker
        transfer::public_transfer(
            coin::from_balance(token_balance, ctx),
            maker
        );

        // Return safety deposit to withdrawer
        (coin::zero<T>(ctx), coin::from_balance(sui_balance, ctx))
    }

    // ============ View Functions ============

    /// Check if a specific secret index can be used for withdrawal
    public fun can_withdraw_with_index<T>(
        escrow: &EscrowDst<T>,
        secret_index: u64,
        clock: &Clock,
        is_public: bool
    ): bool {
        let immutables = get_dst_immutables(escrow);
        let merkle_info = get_dst_merkle_info(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Check if escrow is active
        if (get_dst_status(escrow) != status_active()) {
            return false
        };
        
        // Check timing
        let required_time = if (is_public) {
            get_timelock_stage(get_timelocks(immutables), dst_public_withdrawal())
        } else {
            get_timelock_stage(get_timelocks(immutables), dst_withdrawal())
        };
        if (current_time < required_time) {
            return false
        };
        
        // Check if secret index is already used
        if (is_secret_used(merkle_info, secret_index)) {
            return false
        };
        
        // Check if index is within bounds
        let parts_amount = get_parts_amount(merkle_info) as u64;
        secret_index <= parts_amount
    }

    /// Get the amount that will be withdrawn for a specific secret index
    public fun get_withdrawal_amount<T>(
        escrow: &EscrowDst<T>,
        secret_index: u64
    ): (u64, u64) {
        let immutables = get_dst_immutables(escrow);
        let merkle_info = get_dst_merkle_info(escrow);
        
        let total_amount = get_amount(immutables);
        let parts_amount = get_parts_amount(merkle_info) as u64;
        let fill_amount = calculate_partial_fill_amount(
            total_amount, 
            parts_amount, 
            secret_index
        );
        let sui_amount = calculate_proportional_safety_deposit(
            get_safety_deposit(immutables),
            fill_amount,
            total_amount
        );
        
        (fill_amount, sui_amount)
    }

    /// Get remaining withdrawable amount
    public fun get_remaining_amount<T>(escrow: &EscrowDst<T>): u64 {
        balance::value(&escrow.token_balance)
    }

    /// Get list of used secret indices
    public fun get_used_indices_dst<T>(escrow: &EscrowDst<T>): &vector<u8> {
        let merkle_info = get_dst_merkle_info(escrow);
        get_used_indices(merkle_info)
    }

    /// Get withdrawal recipient (maker)
    public fun get_withdrawal_recipient<T>(escrow: &EscrowDst<T>): address {
        get_maker(get_dst_immutables(escrow))
    }


