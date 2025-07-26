/// Module: escrow
module escrow::utils;

    use escrow::constants;
    use escrow::structs::{Timelocks, MerkleSecretInfo};
    use escrow::structs;
    use sui::hash;
    use sui::bcs;

 // ============ Timelock Functions ============

    /// Get timelock stage timestamp
    public fun get_timelock_stage(timelocks: &Timelocks, stage: u8): u64 {
        let deployed_at = structs::get_deployed_at(timelocks);
        
        if (stage == constants::src_withdrawal()) {
            deployed_at + (structs::get_src_withdrawal_time(timelocks) as u64)
        } else if (stage == constants::src_public_withdrawal()) {
            deployed_at + (structs::get_src_public_withdrawal_time(timelocks) as u64)
        } else if (stage == constants::src_cancellation()) {
            deployed_at + (structs::get_src_cancellation_time(timelocks) as u64)
        } else if (stage == constants::src_public_cancellation()) {
            deployed_at + (structs::get_src_public_cancellation_time(timelocks) as u64)
        } else if (stage == constants::dst_withdrawal()) {
            deployed_at + (structs::get_dst_withdrawal_time(timelocks) as u64)
        } else if (stage == constants::dst_public_withdrawal()) {
            deployed_at + (structs::get_dst_public_withdrawal_time(timelocks) as u64)
        } else if (stage == constants::dst_cancellation()) {
            deployed_at + (structs::get_dst_cancellation_time(timelocks) as u64)
        } else {
            deployed_at
        }
    }

    // ============ Validation Functions ============

    /// Validate secret against hashlock
    public fun validate_secret(secret: &vector<u8>, hashlock: &vector<u8>): bool {
        let hashed = hash::keccak256(secret);
        &hashed == hashlock
    }

    /// Check if a secret index has been used
    public fun is_secret_used(merkle_info: &MerkleSecretInfo, index: u64): bool {
        let used_indices = structs::get_used_indices(merkle_info);
        vector::contains(used_indices, &(index as u8))
    }

    /// Validate partial fill constraints
    public fun validate_partial_fill(
        total_amount: u64,
        remaining_amount: u64,
        fill_amount: u64,
        parts_amount: u64,
        secret_index: u64
    ): bool {
        let filled_amount = total_amount - remaining_amount;
        let expected_index = calculate_expected_index(
            total_amount,
            filled_amount,
            fill_amount,
            parts_amount
        );
        
        // For the last fill, use the extra secret
        if (remaining_amount == fill_amount) {
            expected_index == parts_amount && secret_index == parts_amount
        } else {
            expected_index == secret_index
        }
    }

    /// Calculate expected secret index for partial fill
    fun calculate_expected_index(
        total_amount: u64,
        filled_amount: u64,
        fill_amount: u64,
        parts_amount: u64
    ): u64 {
        // Calculate which part this fill completes
        ((filled_amount + fill_amount - 1) * parts_amount / total_amount)
    }
    // ============ Merkle Proof Functions ============

    /// Verify merkle proof for a secret
    public fun verify_merkle_proof(
        leaf: vector<u8>,
        proof: &vector<vector<u8>>,
        root: &vector<u8>
    ): bool {
        let mut current = leaf;
        let mut i = 0;
        let proof_len = vector::length(proof);
        
        while (i < proof_len) {
            let sibling = vector::borrow(proof, i);
            current = hash_pair(&current, sibling);
            i = i + 1;
        };
        
        &current == root
    }

    /// Create merkle leaf from index and secret hash
    public fun create_merkle_leaf(index: u64, secret_hash: &vector<u8>): vector<u8> {
        let index_bytes = bcs::to_bytes(&index);
        let mut data = index_bytes;
        vector::append(&mut data, *secret_hash);
        hash::keccak256(&data)
    }

    /// Hash two nodes in merkle tree
    fun hash_pair(a: &vector<u8>, b: &vector<u8>): vector<u8> {
        let comparison = compare_bytes(a, b);
        
        if (comparison <= 1) {
            // a <= b
            let mut data = *a;
            vector::append(&mut data, *b);
            hash::keccak256(&data)
        } else {
            // a > b
            let mut data = *b;
            vector::append(&mut data, *a);
            hash::keccak256(&data)
        }
    }

    /// Compare two byte vectors
    /// Returns: 0 if a < b, 1 if a == b, 2 if a > b
    fun compare_bytes(a: &vector<u8>, b: &vector<u8>): u8 {
        let len_a = vector::length(a);
        let len_b = vector::length(b);
        let min_len = if (len_a < len_b) len_a else len_b;
        
        let mut i = 0;
        while (i < min_len) {
            let byte_a = *vector::borrow(a, i);
            let byte_b = *vector::borrow(b, i);
            if (byte_a < byte_b) return 0;
            if (byte_a > byte_b) return 2;
            i = i + 1;
        };
        
        if (len_a < len_b) 0
        else if (len_a > len_b) 2
        else 1
    }

    // ============ Balance Extraction Functions ============

    /// Calculate partial fill amount based on secret index
    public fun calculate_partial_fill_amount(
        total_amount: u64,
        parts_amount: u64,
        secret_index: u64
    ): u64 {
        // Each secret unlocks a proportional amount
        // Index 0 = first part, Index parts_amount = last fill
        if (secret_index == parts_amount) {
            // Last secret fills remaining amount
            total_amount / parts_amount + total_amount % parts_amount
        } else {
            // Regular part
            total_amount / parts_amount
        }
    }

    /// Calculate proportional safety deposit for partial fill
    public fun calculate_proportional_safety_deposit(
        safety_deposit: u64,
        fill_amount: u64,
        total_amount: u64
    ): u64 {
        (safety_deposit * fill_amount) / total_amount
    }






