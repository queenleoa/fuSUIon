/// Module: escrow
module escrow::utils;

    use escrow::constants;
    use escrow::structs::{Timelocks, MerkleSecretInfo};
    use escrow::structs;

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