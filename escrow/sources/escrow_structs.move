/// Module: escrow
module escrow::structs;

    use std::string::String;
    use sui::balance::Balance;
    use sui::sui::SUI;

// ============ Core Structs ============

    /// Timelocks configuration
    public struct Timelocks has copy, drop, store {
        deployed_at: u64,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        src_public_cancellation: u32,
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
    }

    /// Core immutable parameters for an escrow
    public struct EscrowImmutables has copy, drop, store {
        order_hash: vector<u8>,      // 32 bytes
        hashlock: vector<u8>,        // 32 bytes - keccak256(secret) or merkle root
        maker: address,
        taker: address,
        token_type: String,          // Token type identifier
        amount: u64,
        safety_deposit: u64,         // by resolver In SUI
        timelocks: Timelocks,
    }

    