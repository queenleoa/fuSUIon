/// Module: escrow
module escrow::constants;

// ============ Error Constants ============

    /// Error codes for escrow operations (using u8 for efficiency)
    public fun error_invalid_secret(): u64 { 1 }
    public fun error_invalid_timelock(): u64 { 2 }
    public fun error_already_withdrawn(): u64 { 3 }
    public fun error_already_cancelled(): u64 { 4 }
    public fun error_not_authorized(): u64 { 5 }
    public fun error_insufficient_balance(): u64 { 6 }
    public fun error_invalid_status(): u64 { 7 }
    public fun error_secret_already_used(): u64 { 8 }
    public fun error_invalid_merkle_proof(): u64 { 9 }
    public fun error_invalid_partial_fill(): u64 { 10 }
    public fun error_invalid_escrow_params(): u64 { 11 }
    public fun error_invalid_access_token(): u64 { 12 }
    public fun error_timelock_not_expired(): u64 { 13 }
    public fun error_invalid_order_hash(): u64 { 14 }
    public fun error_invalid_amount(): u64 { 15 }
    public fun error_invalid_safety_deposit(): u64 { 16 }
    public fun error_escrow_not_active(): u64 { 17 }
    public fun error_invalid_merkle_index(): u64 { 18 }
    public fun error_invalid_intent_signature(): u64 { 19 }
    public fun error_resolver_not_whitelisted(): u64 { 20 }
    public fun error_invalid_caller(): u64 { 21 }
    public fun error_invalid_time(): u64 { 22 }
    public fun error_token_expired(): u64 { 23 }
    public fun error_invalid_immutables(): u64 { 24 }
    public fun error_invalid_secrets_amount(): u64 { 25 }
    public fun error_invalid_creation_time(): u64 { 26 }
    public fun error_invalid_resolver(): u64 { 27 }


// ============ Status Constants ============

    /// Escrow status values
    public fun status_active(): u8 { 0 }
    public fun status_withdrawn(): u8 { 1 }
    public fun status_cancelled(): u8 { 2 }

// ============ Timelock Stage Constants ============

    /// Timelock stages for validation
    public fun src_withdrawal(): u8 { 0 }
    public fun src_public_withdrawal(): u8 { 1 }
    public fun src_cancellation(): u8 { 2 }
    public fun src_public_cancellation(): u8 { 3 }
    public fun dst_withdrawal(): u8 { 4 }
    public fun dst_public_withdrawal(): u8 { 5 }
    public fun dst_cancellation(): u8 { 6 }

// ============ Intent Action Constants ============

    /// Intent action types
    public fun intent_action_create(): u8 { 0 }
    public fun intent_action_cancel(): u8 { 1 }

// ============ Merkle Tree Constants ============

    /// Constants for merkle tree operations
    public fun max_parts_amount(): u8 { 255 }  // Maximum number of parts an order can be split into
    public fun merkle_root_size(): u64 { 32 }  // Size of merkle root in bytes
    public fun secret_hash_size(): u64 { 32 }  // Size of keccak256 hash in bytes    

// ============ Default Timelock Values (in seconds) ============

    /// Default timelock durations - can be overridden per escrow
    public fun default_src_withdrawal_time(): u64 { 3600 }         // 1 hour
    public fun default_src_public_withdrawal_time(): u64 { 7200 }  // 2 hours
    public fun default_src_cancellation_time(): u64 { 10800 }      // 3 hours
    public fun default_src_public_cancellation_time(): u64 { 14400 } // 4 hours
    public fun default_dst_withdrawal_time(): u64 { 1800 }         // 30 minutes
    public fun default_dst_public_withdrawal_time(): u64 { 3600 }  // 1 hour
    public fun default_dst_cancellation_time(): u64 { 7200 }       // 2 hours

// ============ System Constants ============

    /// Minimum safety deposit amount (in MIST)
    public fun min_safety_deposit(): u64 { 1_000_000_000 }  // 1 SUI

    /// Maximum allowed slippage for partial fills (basis points)
    public fun max_slippage_bps(): u64 { 100 }  // 1%

// ============ Access Token Constants ============

    /// Default token validity period (24 hours in seconds)
    public fun default_token_validity(): u64 { 86400 }

// ============ Signature Constants ============

    /// Sui intent message prefix
    public fun sui_intent_prefix(): vector<u8> { b"SuiSignedMessage"}