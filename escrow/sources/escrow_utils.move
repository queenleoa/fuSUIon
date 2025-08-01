/// Module: escrow
module escrow::utils;

    use sui::hash;
    use escrow::structs::{
        EscrowImmutables, 
        Timelocks, 
        get_src_withdrawal_time,
        get_src_public_withdrawal_time,
        get_src_cancellation_time,
        get_src_public_cancellation_time,
        get_dst_withdrawal_time,
        get_dst_public_withdrawal_time,
        get_dst_cancellation_time,
    };
    use escrow::structs;
    use sui::clock::{Clock, timestamp_ms};
    use escrow::constants::{
        stage_finality_lock,
        stage_resolver_exclusive_withdraw,
        stage_public_withdraw,
        stage_resolver_exclusive_cancel,
        stage_public_cancel,
    };
      

    // ============ Immutables Validation Functions ============

    /// Validate all immutable parameters are properly set
    public(package) fun validate_immutables(immutables: &EscrowImmutables): bool {
        // Validate order hash is 32 bytes
        if (vector::length(structs::get_order_hash(immutables)) != 32) {
            return false
        };
        
        // Validate hashlock is 32 bytes (keccak256)
        if (vector::length(structs::get_hashlock(immutables)) != 32) {
            return false
        };
        
        // Validate addresses are not zero
        if (structs::get_maker(immutables) == @0x0 || 
            structs::get_taker(immutables) == @0x0
            ) {
            return false
        };
        
        // Validate amounts are positive
        if (structs::get_amount(immutables) == 0 || 
            structs::get_safety_deposit_amount(immutables) == 0) {
            return false
        };
        
        true
    }

    // ============ Balance Validation Functions ============

    /// Validate token balance meets required amount
    public(package) fun validate_balance(provided: u64, required: u64): bool {
        provided >= required
    }

    // ============ Hashlock Validation Functions ============

    /// Validate a secret against a hashlock
    public(package) fun validate_hashlock(secret: &vector<u8>, hashlock: &vector<u8>): bool {
        let hashed = hash::keccak256(secret);
        &hashed == hashlock
    }

    /// Check if secret meets minimum length requirements
    public(package) fun validate_secret_length(secret: &vector<u8>): bool {
        vector::length(secret) >= 32
    }

    // ============ Timelock Functions ============

    // -----------------------------------------------------------------------------
    // 1. Validate that a Timelocks struct is sane
    // -----------------------------------------------------------------------------
    public(package) fun is_valid_timelocks(tl: &Timelocks): bool {
        // Monotonic sequence on the destination chain
        let dst_ok =
            get_deployed_at(tl)              < get_dst_withdrawal_time(tl) &&
            get_dst_withdrawal_time(tl)      < get_dst_public_withdrawal_time(tl) &&
            get_dst_public_withdrawal_time(tl) < get_dst_cancellation_time(tl);

        // Monotonic sequence on the source chain
        let src_ok =
            get_src_withdrawal_time(tl)      < get_src_public_withdrawal_time(tl) &&
            get_src_public_withdrawal_time(tl) < get_src_cancellation_time(tl) &&
            get_src_cancellation_time(tl)    < get_src_public_cancellation_time(tl);

        // Cross‑chain ordering (dst deadlines precede src)
        let cross_ok =
            get_dst_withdrawal_time(tl)        < get_src_withdrawal_time(tl) &&
            get_dst_public_withdrawal_time(tl) < get_src_public_withdrawal_time(tl) &&
            get_dst_cancellation_time(tl)      < get_src_cancellation_time(tl);

        // All groups must pass
        dst_ok && src_ok && cross_ok
    }

    // -----------------------------------------------------------------------------
    // 2. Stage helpers (source / destination)
    // -----------------------------------------------------------------------------
    /// Returns one of your stage constants (0‑4) based on the
    /// will implement rescue later
    /// current wall‑clock time *and* the source‑side deadlines.
    public(package) fun src_stage(tl: &Timelocks, clock: &Clock): u8 {
        let now = timestamp_ms(clock);  // use now_seconds() if you store seconds

        if (now < get_src_created_at(tl)) {
            stage_finality_lock()
        } else if (now < get_src_public_withdrawal_time(tl)) {
            // Resolver has exclusive right to reveal the secret
            stage_resolver_exclusive_withdraw()
        } else if (now < get_src_cancellation_time(tl)) {
            // Other resolvers with the secret can withdraw (public phase)
            stage_public_withdraw()
        } else if (now < get_src_public_cancellation_time(tl)) {
            // Resolver can cancel and reclaim deposit
            stage_resolver_exclusive_cancel()
        } else {
            // Any resolver (or anyone) can cancel to free stuck funds
            stage_public_cancel()
        }
    }

    /// Destination side has fewer windows: withdraw, public withdraw,
    /// cancel. After `dst_cancellation` the source chain’s logic takes over.
    public(package) fun dst_stage(tl: &Timelocks, clock: &Clock): u8 {
        let now = timestamp_ms(clock);  // use now_seconds() if you store seconds

        if (now < get_dst_created_at(tl)) {
            stage_finality_lock()
        } else if (now < get_dst_public_withdrawal_time(tl)) {
            stage_resolver_exclusive_withdraw()
        } else if (now < get_dst_cancellation_time(tl)) {
            stage_public_withdraw()
        } else {
            // Past destination cancel deadline; resolver can reclaim
            stage_resolver_exclusive_cancel()
            // (You could also return stage_public_cancel if you prefer.)
        }
    }

    //dutch auction curve
    public fun calc_taker_amount(
            start_time: u64,
            end_time: u64,
            taking_amount_start: u128,
            taking_amount_end: u128,
            clock: &Clock,
        ): u128 {
            // --- sanity ---------------------------------------------------------
            assert!(start_time < end_time, 0);

            // --- clamp current time into the auction window ---------------------
            let now_ms = timestamp_ms(clock);
            let t = if (now_ms < start_time) {
                start_time
            } else if (now_ms > end_time) {
                end_time
            } else {
                now_ms
            };

            // --- cast once; avoids repeated casting clutter ---------------------
            let t_u128          = t as u128;
            let start_time_u128 = start_time as u128;
            let end_time_u128   = end_time as u128;

            // --- linear interpolation ------------------------------------------
            let elapsed        = t_u128 - start_time_u128;          // (t − T₀)
            let remaining      = end_time_u128 - t_u128;            // (T₁ − t)
            let duration       = end_time_u128 - start_time_u128;   // (T₁ − T₀)

            let weighted_start = taking_amount_start * remaining;   // A₀ · (T₁ − t)
            let weighted_end   = taking_amount_end   * elapsed;     // A₁ · (t − T₀)

            (weighted_start + weighted_end) / duration              // Aₜ
        }
