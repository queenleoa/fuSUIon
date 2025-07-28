/// Module: escrow
module escrow::utils;

    use sui::hash;
    use sui::bcs;
    use escrow::constants;
    use escrow::structs::{
        EscrowImmutables, 
        Timelocks, 
        OrderState,
        AccessToken,
    };
    use escrow::structs;
    use sui::clock::{Clock, timestamp_ms};

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
            structs::get_taker(immutables) == @0x0 ||
            structs::get_resolver(immutables) == @0x0) {
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

    /// Calculate proportional amounts for partial fills
    public(package) fun calculate_partial_fill_amount(
        total_amount: u64,
        parts_amount: u64,
        secret_index: u64
    ): u64 {
        if (secret_index == parts_amount) {
            // Last fill gets any remaining dust
            total_amount / parts_amount + (total_amount % parts_amount)
        } else {
            // Regular partial fill
            total_amount / parts_amount
        }
    }

    /// Calculate proportional safety deposit for partial fill
    public(package) fun calculate_proportional_safety_deposit(
        total_safety_deposit: u64,
        fill_amount: u64,
        total_amount: u64
    ): u64 {
        (total_safety_deposit * fill_amount) / total_amount
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

    /// Get absolute timestamp for a timelock stage
    public(package) fun get_timelock_stage(timelocks: &Timelocks, stage: u8): u64 {
        let deployed_at = structs::get_deployed_at(timelocks);
        
        if (stage == constants::src_withdrawal()) {
            deployed_at + structs::get_src_withdrawal_time(timelocks)
        } else if (stage == constants::src_public_withdrawal()) {
            deployed_at + structs::get_src_public_withdrawal_time(timelocks)
        } else if (stage == constants::src_cancellation()) {
            deployed_at + structs::get_src_cancellation_time(timelocks)
        } else if (stage == constants::src_public_cancellation()) {
            deployed_at + structs::get_src_public_cancellation_time(timelocks)
        } else if (stage == constants::dst_withdrawal()) {
            deployed_at + structs::get_dst_withdrawal_time(timelocks)
        } else if (stage == constants::dst_public_withdrawal()) {
            deployed_at + structs::get_dst_public_withdrawal_time(timelocks)
        } else if (stage == constants::dst_cancellation()) {
            deployed_at + structs::get_dst_cancellation_time(timelocks)
        } else {
            deployed_at
        }
    }

    /// Check if current time has passed a timelock stage
    public(package) fun has_timelock_expired(timelocks: &Timelocks, stage: u8, clock: &Clock): bool {
        let current_time = timestamp_ms(clock) / 1000;
        let stage_time = get_timelock_stage(timelocks, stage);
        current_time >= stage_time
    }

    /// Validate timelocks are properly ordered
    public(package) fun validate_timelocks(timelocks: &Timelocks): bool {
        let deployed = structs::get_deployed_at(timelocks);
        let src_withdraw = structs::get_src_withdrawal_time(timelocks);
        let src_public_withdraw = structs::get_src_public_withdrawal_time(timelocks);
        let src_cancel = structs::get_src_cancellation_time(timelocks);
        let src_public_cancel = structs::get_src_public_cancellation_time(timelocks);
        let dst_withdraw = structs::get_dst_withdrawal_time(timelocks);
        let dst_public_withdraw = structs::get_dst_public_withdrawal_time(timelocks);
        let dst_cancel = structs::get_dst_cancellation_time(timelocks);
        
        // Validate ordering: withdrawal < public_withdrawal < cancellation < public_cancellation
        src_withdraw < src_public_withdraw &&
        src_cancel < src_public_cancel &&
        dst_withdraw < dst_public_withdraw &&
        
        // Validate minimums (all times should be positive)
        src_withdraw > 0 &&
        dst_withdraw > 0 &&
        src_cancel > 0 &&
        dst_cancel > 0
    }

    // ============ Merkle Tree Functions ============

    /// Create a merkle leaf from index and secret hash
    public(package) fun create_merkle_leaf(index: u64, secret_hash: &vector<u8>): vector<u8> {
        let mut leaf_data = bcs::to_bytes(&index);
        vector::append(&mut leaf_data, *secret_hash);
        hash::keccak256(&leaf_data)
    }

    /// Hash two merkle nodes together (sorted to ensure consistency)
    fun hash_merkle_pair(left: &vector<u8>, right: &vector<u8>): vector<u8> {
        let mut combined = vector::empty<u8>();
        
        // Sort nodes to ensure consistent hashing regardless of order
        if (compare_bytes(left, right) < 0) {
            vector::append(&mut combined, *left);
            vector::append(&mut combined, *right);
        } else {
            vector::append(&mut combined, *right);
            vector::append(&mut combined, *left);
        };
        
        hash::keccak256(&combined)
    }

    /// Verify a merkle proof for a given leaf
    public(package) fun verify_merkle_proof(
        leaf: vector<u8>,
        proof: &vector<vector<u8>>,
        root: &vector<u8>
    ): bool {
        let mut current = leaf;
        let proof_len = vector::length(proof);
        let mut i = 0;
        
        while (i < proof_len) {
            let sibling = vector::borrow(proof, i);
            current = hash_merkle_pair(&current, sibling);
            i = i + 1;
        };
        
        &current == root
    }

    /// Check if a secret index has been used in the order state
    public(package) fun is_secret_used(order_state: &OrderState, index: u64): bool {
        let used_indices = structs::get_order_state_used_indices(order_state);
        vector::contains(used_indices, &(index as u8))
    }

    /// Validate merkle parameters for an order
    public(package) fun validate_merkle_params(
        merkle_root: &vector<u8>,
        parts_amount: u8,
        secret_index: u64
    ): bool {
        // Merkle root should be 32 bytes if present
        let has_merkle = vector::length(merkle_root) > 0;
        
        if (has_merkle) {
            // Validate merkle root is exactly 32 bytes
            if (vector::length(merkle_root) != 32) {
                return false
            };
            
            // Validate parts amount is reasonable
            if (parts_amount == 0 || parts_amount > constants::max_parts_amount()) {
                return false
            };
            
            // Validate secret index is within bounds (0 to parts_amount inclusive)
            if (secret_index > (parts_amount as u64)) {
                return false
            };
        } else {
            // Non-merkle orders should have parts_amount = 0
            if (parts_amount != 0) {
                return false
            };
        };
        
        true
    }

    /// Calculate expected index for partial fill validation
    public(package) fun calculate_expected_index(
        total_amount: u64,
        filled_amount: u64,
        fill_amount: u64,
        parts_amount: u64
    ): u64 {
        ((filled_amount + fill_amount - 1) * parts_amount) / total_amount
    }

    /// Validate a partial fill is valid for the current state
    public(package) fun validate_partial_fill(
        total_amount: u64,
        filled_amount: u64,
        fill_amount: u64,
        parts_amount: u64,
        secret_index: u64
    ): bool {
        let remaining_amount = total_amount - filled_amount;
        
        // Check if fill amount exceeds remaining
        if (fill_amount > remaining_amount) {
            return false
        };
        
        let expected_index = calculate_expected_index(
            total_amount,
            filled_amount,
            fill_amount,
            parts_amount
        );
        
        // For the last fill, must use the extra secret (parts_amount)
        if (remaining_amount == fill_amount) {
            return secret_index == parts_amount
        };
        
        // For regular fills, check index matches expected
        if (filled_amount > 0) {
            // Calculate previous index to ensure no overlap
            let prev_index = calculate_expected_index(
                total_amount,
                filled_amount - 1,
                1,
                parts_amount
            );
            
            // Ensure we're not reusing the same index
            if (expected_index == prev_index) {
                return false
            };
        };
        
        expected_index == secret_index
    }

    // ============ Access Token Validation ============

    /// Validate an access token is valid for a resolver
    public(package) fun validate_access_token(
        token: &AccessToken,
        resolver: address,
        clock: &Clock
    ): bool {
        // Check resolver matches
        if (structs::get_token_resolver(token) != resolver) {
            return false
        };
        
        // Check not expired
        let current_time = timestamp_ms(clock) / 1000;
        let expires_at = structs::get_token_expires_at(token);
        
        current_time < expires_at
    }

    // ============ Intent Signature Validation ============

    /// Validate user intent parameters match escrow
    public(package) fun validate_intent_params(
        order_hash: &vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        provided_hash: &vector<u8>,
        provided_maker: address,
        provided_taker: address,
        provided_amount: u64
    ): bool {
        order_hash == provided_hash &&
        maker == provided_maker &&
        taker == provided_taker &&
        amount == provided_amount
    }

    // ============ Helper Functions ============

    /// Compare two byte vectors lexicographically
    fun compare_bytes(a: &vector<u8>, b: &vector<u8>): u8 {
        let len_a = vector::length(a);
        let len_b = vector::length(b);
        let min_len = if (len_a < len_b) { len_a } else { len_b };
        
        let mut i = 0;
        while (i < min_len) {
            let byte_a = *vector::borrow(a, i);
            let byte_b = *vector::borrow(b, i);
            
            if (byte_a < byte_b) {
                return 0 // a < b
            } else if (byte_a > byte_b) {
                return 2 // a > b
            };
            
            i = i + 1;
        };
        
        // If all bytes are equal up to min_len, shorter vector is smaller
        if (len_a < len_b) {
            0 // a < b
        } else if (len_a > len_b) {
            2 // a > b
        } else {
            1 // a == b
        }
    }

    /// Check if an amount would cause overflow when added
    public(package) fun check_overflow_add(a: u64, b: u64): bool {
        // In Move, arithmetic operations abort on overflow
        // This function checks if addition would overflow
        let max_u64 = 18446744073709551615;
        a <= max_u64 - b
    }

    /// Check if multiplication would cause overflow
    public(package) fun check_overflow_mul(a: u64, b: u64): bool {
        if (a == 0 || b == 0) {
            return true
        };
        let max_u64 = 18446744073709551615;
        a <= max_u64 / b
    }

    // ============ Tests ============
    
    #[test]
    fun test_hashlock_validation() {
        let secret = b"this_is_a_secret_at_least_32_bytes_long_for_testing";
        let hashlock = hash::keccak256(&secret);
        
        assert!(validate_hashlock(&secret, &hashlock), 0);
        
        let wrong_secret = b"wrong_secret_that_is_also_32_bytes_long_for_testing";
        assert!(!validate_hashlock(&wrong_secret, &hashlock), 1);
    }

    #[test]
    fun test_merkle_leaf_creation() {
        let index = 5u64;
        let secret = b"test_secret";
        let secret_hash = hash::keccak256(&secret);
        
        let leaf = create_merkle_leaf(index, &secret_hash);
        assert!(vector::length(&leaf) == 32, 0);
    }

    #[test]
    fun test_partial_fill_calculation() {
        let total = 1000u64;
        let parts = 10u64;
        
        // Regular fill
        let fill_amount = calculate_partial_fill_amount(total, parts, 0);
        assert!(fill_amount == 100, 0);
        
        // Last fill gets remainder
        let last_fill = calculate_partial_fill_amount(total, parts, parts);
        assert!(last_fill == 100, 1);
        
        // Test with remainder
        let total_with_remainder = 1005u64;
        let last_fill_remainder = calculate_partial_fill_amount(total_with_remainder, parts, parts);
        assert!(last_fill_remainder == 105, 2); // 100 + 5 remainder
    }
