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

    // Merkle secret tree info for partial fills
    public struct MerkleSecretInfo has copy, drop, store {
        merkle_root: vector<u8>,     // 32 bytes
        parts_amount: u8,            // Number of parts the order is split into
        used_indices: vector<u8>,    // Indices of used secrets
    }

    /// Source chain escrow object - SHARED for consensus
    public struct EscrowSrc<phantom T> has key, store {
        id: UID,
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        sui_balance: Balance<SUI>,
        status: u8,
        merkle_info: MerkleSecretInfo,
    }

    /// Destination chain escrow object - SHARED for consensus
    public struct EscrowDst<phantom T> has key, store {
        id: UID,
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        sui_balance: Balance<SUI>,
        status: u8,
        merkle_info: MerkleSecretInfo
    }

    /// Access token for public operations
    public struct AccessToken has key, store {
        id: UID,
        created_at: u64,
    }

    /// Factory for creating escrows - SHARED object
    public struct EscrowFactory has key {
        id: UID,
        rescue_delay: u64,
        access_token_supply: u64,
    }


