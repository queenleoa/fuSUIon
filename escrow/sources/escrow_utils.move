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

    /// Mark a secret index as used
    public(package) fun mark_secret_used(merkle_info: &mut MerkleSecretInfo, index: u64) {
        vector::push_back(&mut merkle_info.used_indices, index as u8);
    }

    
