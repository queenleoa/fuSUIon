/// Module: escrow
/*module escrow::escrow_dst_withdraw_merkle;

    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
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
        dst_token_balance_value
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
         //── 1️⃣  Grab all read-only data first ───────────────────
    let maker          = get_maker(get_dst_immutables(escrow));
    let total_amount   = get_amount(get_dst_immutables(escrow));
    let safety_deposit = get_safety_deposit(get_dst_immutables(escrow));
    let parts_amount   = get_parts_amount(get_dst_merkle_info(escrow)) as u64;

    //── 2️⃣  Now we’re free to mutate escrow ─────────────────
    mark_secret_used(get_dst_merkle_info_mut(escrow), secret_index);

    //── 3️⃣  Compute proportional amounts  ───────────────────
    let fill_amount = calculate_partial_fill_amount(
        total_amount, parts_amount, secret_index
    );
    let sui_amount  = calculate_proportional_safety_deposit(
        safety_deposit, fill_amount, total_amount
    );

    //── 4️⃣  Pull coins out of the escrow  ───────────────────
    let (token_bal, sui_bal) = extract_proportional_dst_balances(
        escrow, fill_amount, sui_amount
    );

    //── 5️⃣  If nothing left, flip status  ───────────────────
    if (dst_token_balance_value(escrow) == 0) {
        set_dst_status(escrow, status_withdrawn());
    };

    //── 6️⃣  Emit event & pay maker  ─────────────────────────
    events::emit_escrow_withdrawn(
        get_dst_id(escrow),
        secret,
        maker,
        fill_amount,
        secret_index,
    );

    transfer::public_transfer(
        coin::from_balance(token_bal, ctx),  // tokens → maker
        maker
    );

    //*── 7️⃣  Return the SUI safety-deposit to caller ─────────
    (coin::zero<T>(ctx), coin::from_balance(sui_bal, ctx))
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
        dst_token_balance_value(escrow)
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


