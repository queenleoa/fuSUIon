/// Module: escrow
module escrow::utils;

    use escrow::constants;
    use escrow::structs::{Timelocks, MerkleSecretInfo};
    use escrow::structs;
    use sui::hash;

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

    



