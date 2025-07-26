/// Module: escrow
module escrow::structs;

    use std::string::String;
    use sui::balance::Balance;
    use sui::sui::SUI;
    use escrow::constants::status_active;

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

     // ============ Constructor Functions ============

    public fun new_timelocks(
        deployed_at: u64,
        src_withdrawal: u32,
        src_public_withdrawal: u32,
        src_cancellation: u32,
        src_public_cancellation: u32,
        dst_withdrawal: u32,
        dst_public_withdrawal: u32,
        dst_cancellation: u32,
    ): Timelocks {
        Timelocks {
            deployed_at,
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            src_public_cancellation,
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
        }
    }

    public fun new_immutables(
        order_hash: vector<u8>,
        hashlock: vector<u8>,
        maker: address,
        taker: address,
        token_type: String,
        amount: u64,
        safety_deposit: u64,
        timelocks: Timelocks,
    ): EscrowImmutables {
        EscrowImmutables {
            order_hash,
            hashlock,
            maker,
            taker,
            token_type,
            amount,
            safety_deposit,
            timelocks,
        }
    }

    public fun new_merkle_info(
        merkle_root: vector<u8>,
        parts_amount: u8,
    ): MerkleSecretInfo {
        MerkleSecretInfo {
            merkle_root,
            parts_amount,
            used_indices: vector::empty(),
        }
    }

    // ============ Getter Functions ============

    // Timelocks getters
    public fun get_deployed_at(timelocks: &Timelocks): u64 { timelocks.deployed_at }
    public fun get_src_withdrawal_time(timelocks: &Timelocks): u32 { timelocks.src_withdrawal }
    public fun get_src_public_withdrawal_time(timelocks: &Timelocks): u32 { timelocks.src_public_withdrawal }
    public fun get_src_cancellation_time(timelocks: &Timelocks): u32 { timelocks.src_cancellation }
    public fun get_src_public_cancellation_time(timelocks: &Timelocks): u32 { timelocks.src_public_cancellation }
    public fun get_dst_withdrawal_time(timelocks: &Timelocks): u32 { timelocks.dst_withdrawal }
    public fun get_dst_public_withdrawal_time(timelocks: &Timelocks): u32 { timelocks.dst_public_withdrawal }
    public fun get_dst_cancellation_time(timelocks: &Timelocks): u32 { timelocks.dst_cancellation }

    // EscrowImmutables getters
    public fun get_order_hash(immutables: &EscrowImmutables): &vector<u8> { &immutables.order_hash }
    public fun get_hashlock(immutables: &EscrowImmutables): &vector<u8> { &immutables.hashlock }
    public fun get_maker(immutables: &EscrowImmutables): address { immutables.maker }
    public fun get_taker(immutables: &EscrowImmutables): address { immutables.taker }
    public fun get_token_type(immutables: &EscrowImmutables): &String { &immutables.token_type }
    public fun get_amount(immutables: &EscrowImmutables): u64 { immutables.amount }
    public fun get_safety_deposit(immutables: &EscrowImmutables): u64 { immutables.safety_deposit }
    public fun get_timelocks(immutables: &EscrowImmutables): &Timelocks { &immutables.timelocks }

    // MerkleSecretInfo getters
    public fun get_merkle_root(info: &MerkleSecretInfo): &vector<u8> { &info.merkle_root }
    public fun get_parts_amount(info: &MerkleSecretInfo): u8 { info.parts_amount }
    public fun get_used_indices(info: &MerkleSecretInfo): &vector<u8> { &info.used_indices }

    // EscrowSrc getters
    public fun get_src_id<T>(escrow: &EscrowSrc<T>): address { object::uid_to_address(&escrow.id) }
    public fun get_src_immutables<T>(escrow: &EscrowSrc<T>): &EscrowImmutables { &escrow.immutables }
    public fun get_src_status<T>(escrow: &EscrowSrc<T>): u8 { escrow.status }
    public fun get_src_token_balance<T>(escrow: &EscrowSrc<T>): &Balance<T> { &escrow.token_balance}
    public fun get_src_sui_balance<T>(escrow: &EscrowSrc<T>): &Balance<SUI> { &escrow.sui_balance}
    public fun get_src_merkle_info<T>(escrow: &EscrowSrc<T>): &MerkleSecretInfo { &escrow.merkle_info }

    // EscrowDst getters
    public fun get_dst_id<T>(escrow: &EscrowDst<T>): address { object::uid_to_address(&escrow.id) }
    public fun get_dst_immutables<T>(escrow: &EscrowDst<T>): &EscrowImmutables { &escrow.immutables }
    public fun get_dst_status<T>(escrow: &EscrowDst<T>): u8 { escrow.status }
    public fun get_dst_token_balance<T>(escrow: &EscrowDst<T>): &Balance<T> { &escrow.token_balance}
    public fun get_dst_sui_balance<T>(escrow: &EscrowDst<T>): &Balance<SUI> { &escrow.sui_balance}
    public fun get_dsy_merkle_info<T>(escrow: &EscrowDst<T>): &MerkleSecretInfo { &escrow.merkle_info }

    // Factory getters
    public fun get_rescue_delay(factory: &EscrowFactory): u64 { factory.rescue_delay }
    public fun get_access_token_supply(factory: &EscrowFactory): u64 { factory.access_token_supply }

    // Access token getter
    public fun get_access_token_created_at(access_token: &AccessToken): u64 { access_token.created_at}


    // ============ Escrow Creation Functions ============

    // EscrowSrc setter
    public(package) fun new_escrow_src<T>(
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        sui_balance: Balance<SUI>,
        merkle_info: MerkleSecretInfo,
        ctx: &mut TxContext,
    ): EscrowSrc<T> {
        EscrowSrc {
            id: object::new(ctx),
            immutables,
            token_balance,
            sui_balance,
            status: status_active(),
            merkle_info,
        }
    }

    // EscrowDst setter 
    public(package) fun new_escrow_dst<T>(
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        sui_balance: Balance<SUI>,
        merkle_info: MerkleSecretInfo,
        ctx: &mut TxContext,
    ): EscrowDst<T> {
        EscrowDst {
            id: object::new(ctx),
            immutables,
            token_balance,
            sui_balance,
            status: status_active(),
            merkle_info,
        }
    }

    // AccessToken setter
    public(package) fun new_access_token(
        created_at: u64,
        ctx: &mut TxContext
    ): AccessToken {
        AccessToken {
            id: object::new(ctx),
            created_at,
        }
    }

    // ============ Status Update Functions ============

    // EscrowSrc status setter
    public(package) fun set_src_status<T>(escrow: &mut EscrowSrc<T>, status: u8) {
        escrow.status = status;
    }

    // EscrowDst status setter
    public(package) fun set_dst_status<T>(escrow: &mut EscrowDst<T>, status: u8) {
        escrow.status = status;
    }



