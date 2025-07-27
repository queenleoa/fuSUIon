/// Module: escrow
module escrow::escrow_src_withdraw_merkle;

    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
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
        get_used_indices,
        src_token_balance_value
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
// ============ Internal Functions ============

    /// Execute the merkle withdrawal logic
    fun execute_merkle_withdrawal<T>(
        escrow: &mut EscrowSrc<T>,
        secret: vector<u8>,
        secret_index: u64,
        target: address,
        ctx: &mut TxContext
    ): (Coin<T>, Coin<SUI>) {
        /* ── 1️⃣  Read-only data FIRST (short borrows) ─────────── */
    let total_amount  = get_amount(get_src_immutables(escrow));
    let parts_amount  = get_parts_amount(get_src_merkle_info(escrow)) as u64;
    let safety_deposit = get_safety_deposit(get_src_immutables(escrow));

    /* ── 2️⃣  Mutate once references are gone ──────────────── */
    mark_secret_used(get_merkle_info_mut(escrow), secret_index);

    let fill_amount = calculate_partial_fill_amount(
        total_amount, parts_amount, secret_index
    );
    let sui_amount  = calculate_proportional_safety_deposit(
        safety_deposit, fill_amount, total_amount
    );

    /* ── 3️⃣  Move tokens/SUI out of the escrow ─────────────── */
    let (token_bal, sui_bal) = extract_proportional_src_balances(
        escrow, fill_amount, sui_amount
    );

    /* ── 4️⃣  If everything gone, flip status ──────────────── */
    if (src_token_balance_value(escrow) == 0) {
        set_src_status(escrow, status_withdrawn());
    };

    /* ── 5️⃣  Emit & return ────────────────────────────────── */
    events::emit_escrow_withdrawn(
        get_src_id(escrow),
        secret,
        target,
        fill_amount,
        secret_index,
    );

    (coin::from_balance(token_bal, ctx),
     coin::from_balance(sui_bal,  ctx))
    }

    // ============ View Functions ============

    /// Check if a specific secret index can be used for withdrawal
    public fun can_withdraw_with_index<T>(
        escrow: &EscrowSrc<T>,
        secret_index: u64,
        clock: &Clock
    ): bool {
        let immutables = get_src_immutables(escrow);
        let merkle_info = get_src_merkle_info(escrow);
        let current_time = clock::timestamp_ms(clock) / 1000;
        
        // Check if escrow is active
        if (get_src_status(escrow) != status_active()) {
            return false
        };
        
        // Check timing
        let withdrawal_time = get_timelock_stage(
            get_timelocks(immutables), 
            src_withdrawal()
        );
        if (current_time < withdrawal_time) {
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
        escrow: &EscrowSrc<T>,
        secret_index: u64
    ): (u64, u64) {
        let immutables = get_src_immutables(escrow);
        let merkle_info = get_src_merkle_info(escrow);
        
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
    public fun get_remaining_amount<T>(escrow: &EscrowSrc<T>): u64 {
        src_token_balance_value(escrow)
    }

    /// Get list of used secret indices
    public fun get_used_indices_src<T>(escrow: &EscrowSrc<T>): &vector<u8> {
        let merkle_info = get_src_merkle_info(escrow);
        get_used_indices(merkle_info)
    }


