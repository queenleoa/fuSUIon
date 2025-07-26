/// Module: escrow
module escrow::constants;

    // ============ Error Constants ============
    
    public fun error_invalid_caller(): u64 { 1 }
    public fun error_invalid_secret(): u64 { 2 }
    public fun error_invalid_time(): u64 { 3 }
    public fun error_invalid_immutables(): u64 { 4 }
    public fun error_insufficient_balance(): u64 { 5 }
    public fun error_invalid_creation_time(): u64 { 6 }
    public fun error_already_withdrawn(): u64 { 7 }
    public fun error_already_cancelled(): u64 { 8 }
    public fun error_invalid_merkle_proof(): u64 { 9 }
    public fun error_invalid_partial_fill(): u64 { 10 }
    public fun error_secret_already_used(): u64 { 11 }
    public fun error_invalid_secrets_amount(): u64 { 12 }

