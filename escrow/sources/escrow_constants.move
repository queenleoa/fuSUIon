/// Module: escrow
module escrow::constants;

// ============ Status Constants ============

    /// Escrow status values
    public fun status_active(): u8 { 0 }
    public fun status_withdrawn(): u8 { 1 }
    public fun status_cancelled(): u8 { 2 }

// ============ Timelock Stage Constants ============

    /// Timelock stages
    public fun stage_finality_lock(): u8 { 0 }
    public fun stage_hashlock_unlock(): u8 { 1 }
    public fun stage_resolver_exclusive_withdraw(): u8 { 2 }
    public fun stage_public_withdraw(): u8 { 3 }
    public fun stage_resolver_exclusive_cancel(): u8 { 4 }
    public fun stage_public_cancel(): u8 { 5 }
    public fun stage_rescue(): u8 { 6 }

// ============ Vault Configuration ============
    
    /// Maximum number of buckets per vault
    public fun max_buckets_per_vault(): u64 { 100 }
    
    /// Minimum safety deposit amount (in MIST)
    public fun min_safety_deposit(): u64 { 100_000_000 } // 0.1 SUI

// ============ Error Codes ============
    
    /// Error when vault is full
    public fun e_vault_full(): u64 { 1001 }
    
    /// Error when bucket not found
    public fun e_bucket_not_found(): u64 { 1002 }
    
    /// Error when invalid hashlock
    public fun e_invalid_hashlock(): u64 { 1003 }
    
    /// Error when invalid secret
    public fun e_invalid_secret(): u64 { 1004 }
    
    /// Error when timelock not expired
    public fun e_timelock_not_expired(): u64 { 1005 }
    
    /// Error when action not allowed in current stage
    public fun e_invalid_stage(): u64 { 1006 }
    
    /// Error when insufficient balance
    public fun e_insufficient_balance(): u64 { 1007 }
    
    /// Error when unauthorized access
    public fun e_unauthorized(): u64 { 1008 }
    
    /// Error when bucket already exists
    public fun e_bucket_already_exists(): u64 { 1009 }
    
    /// Error when invalid amount
    public fun e_invalid_amount(): u64 { 1010 }
    
    /// Error when vault is empty
    public fun e_vault_empty(): u64 { 1011 }
    
    /// Error when rescue period not reached
    public fun e_rescue_period_not_reached(): u64 { 1012 }
    
    /// Error when bucket status is invalid for operation
    public fun e_invalid_bucket_status(): u64 { 1013 }
    
    /// Error when safety deposit is too low
    public fun e_safety_deposit_too_low(): u64 { 1014 }