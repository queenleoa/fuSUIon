/// Module: escrow
module escrow::structs;

    use std::string::String;
    use sui::balance::{Balance, split, withdraw_all, destroy_zero};
    use sui::sui::SUI;
    use escrow::constants::{status_active, error_secret_already_used};

// ============ Core Structs ============

    /// Core immutable parameters for escrow operations
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

    /// Merkle secret tree info for partial fills
    /// protect used indices from replay bugs by omitting copy and drop
    public struct MerkleSecretInfo has store {
        merkle_root: vector<u8>,     // 32 bytes
        parts_amount: u8,            // Number of parts the order is split into
        used_indices: vector<u8>,    // Indices of used secrets
    }

    /// Source chain escrow object - SHARED for consensus
    /// holds maker tokens
    public struct EscrowSrc<phantom T> has key, store {
        id: UID,
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        sui_balance: Balance<SUI>,
        status: u8,
        merkle_info: MerkleSecretInfo,
    }

    /// Destination chain escrow object - SHARED for consensus
    /// holds taker tokens
    public struct EscrowDst<phantom T> has key, store {
        id: UID,
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        sui_balance: Balance<SUI>,
        status: u8,
        merkle_info: MerkleSecretInfo
    }

    /// Factory state for global configuration
    public struct AccessFactory has key {
        id: UID,
        rescue_delay: u64,
        access_token_supply: u64,
        admin: address,
    }

    /// Access token for public operations with expiration
    public struct AccessToken has key, store {
        id: UID,
        created_at: u64,
        expires_at: u64,
        escrow_id: Option<address>,
        used: bool,
    }

    /// Timelocks packed into u256
    public struct Timelocks has store, copy, drop {
        value: u256,
    }

     // ============ Constructor Functions ============

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

    public fun new_timelocks(value: u256): Timelocks {
        Timelocks { value }
    }

    // ============ Getter Functions ============

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
    public fun get_dst_merkle_info<T>(escrow: &EscrowDst<T>): &MerkleSecretInfo { &escrow.merkle_info }

    // Factory getters
    public fun get_rescue_delay(factory: &AccessFactory): u64 { factory.rescue_delay }
    public fun get_access_token_supply(factory: &AccessFactory): u64 { factory.access_token_supply }
    public fun get_admin(factory: &AccessFactory): address { factory.admin }

    // Access token getter
    public fun get_access_token_created_at(access_token: &AccessToken): u64 { access_token.created_at }
    public fun get_access_token_expires_at(access_token: &AccessToken): u64 { access_token.expires_at }
    public fun get_access_token_escrow_id(access_token: &AccessToken): &Option<address> { &access_token.escrow_id }
    public fun is_access_token_used(access_token: &AccessToken): bool { access_token.used }
    public fun get_access_token_address(tok: &AccessToken): address { object::uid_to_address(&tok.id) }

    // Timelocks getter
    public fun get_timelocks_value(timelocks: &Timelocks): u256 { timelocks.value }

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
        expires_at: u64,
        escrow_id: Option<address>,
        ctx: &mut TxContext
    ): AccessToken {
        AccessToken {
            id: object::new(ctx),
            created_at,
            expires_at,
            escrow_id,
            used: false,
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

    public(package) fun mark_access_token_used(token: &mut AccessToken) {
        token.used = true;
    }

    // ============ Balance Extraction Functions ============

    public(package) fun extract_src_balances<T>(
        escrow: &mut EscrowSrc<T>
    ): (Balance<T>, Balance<SUI>) {
        let token_balance = withdraw_all(&mut escrow.token_balance);
        let sui_balance = withdraw_all(&mut escrow.sui_balance);
        (token_balance, sui_balance)
    }

    public(package) fun extract_dst_balances<T>(
        escrow: &mut EscrowDst<T>
    ): (Balance<T>, Balance<SUI>) {
        let token_balance = withdraw_all(&mut escrow.token_balance);
        let sui_balance = withdraw_all(&mut escrow.sui_balance);
        (token_balance, sui_balance)
    }

    public(package) fun extract_proportional_src_balances<T>(
        escrow: &mut EscrowSrc<T>,
        token_amount: u64,
        sui_amount: u64
    ): (Balance<T>, Balance<SUI>) {
        let token_balance = split(&mut escrow.token_balance, token_amount);
        let sui_balance = split(&mut escrow.sui_balance, sui_amount);
        (token_balance, sui_balance)
    }

    public(package) fun extract_proportional_dst_balances<T>(
        escrow: &mut EscrowDst<T>,
        token_amount: u64,
        sui_amount: u64
    ): (Balance<T>, Balance<SUI>) {
        let token_balance = split(&mut escrow.token_balance, token_amount);
        let sui_balance = split(&mut escrow.sui_balance, sui_amount);
        (token_balance, sui_balance)
    }

    // ============ Balance Value Functions ============

    public fun src_token_balance_value<T>(escrow: &EscrowSrc<T>): u64 {
        sui::balance::value(&escrow.token_balance)
    }
    
    public fun dst_token_balance_value<T>(escrow: &EscrowDst<T>): u64 {
        sui::balance::value(&escrow.token_balance)
    }

    public fun src_sui_balance_value<T>(escrow: &EscrowSrc<T>): u64 {
        sui::balance::value(&escrow.sui_balance)
    }

    public fun dst_sui_balance_value<T>(escrow: &EscrowDst<T>): u64 {
        sui::balance::value(&escrow.sui_balance)
    }

    // ============ Merkle Info Functions ============

    public(package) fun get_merkle_info_mut<T>(escrow: &mut EscrowSrc<T>): &mut MerkleSecretInfo {
        &mut escrow.merkle_info
    }

    public(package) fun get_dst_merkle_info_mut<T>(escrow: &mut EscrowDst<T>): &mut MerkleSecretInfo {
        &mut escrow.merkle_info
    }

    /// Mark a secret index as used
    public(package) fun mark_secret_used(merkle_info: &mut MerkleSecretInfo, index: u64) {
        // Check if already used before marking
        assert!(!is_secret_index_used(merkle_info, index), error_secret_already_used());
        vector::push_back(&mut merkle_info.used_indices, index as u8);
    }

    /// Check if a secret index has been used
    public fun is_secret_index_used(merkle_info: &MerkleSecretInfo, index: u64): bool {
        let used_indices = &merkle_info.used_indices;
        let mut i = 0;
        let len = vector::length(used_indices);
        while (i < len) {
            if (*vector::borrow(used_indices, i) as u64 == index) {
                return true
            };
            i = i + 1;
        };
        false
    }

    // ============ Factory State Functions ============

    public(package) fun increment_access_token_supply(factory: &mut AccessFactory) {
        factory.access_token_supply = factory.access_token_supply + 1;
    }

    public(package) fun update_rescue_delay(factory: &mut AccessFactory, new_delay: u64) {
        factory.rescue_delay = new_delay;
    }

    public(package) fun set_factory_admin(factory: &mut AccessFactory, new_admin: address) {
        factory.admin = new_admin;
    }

    // ============ Object Cleanup Functions ============

    /// Clean up completed source escrow
    public(package) fun cleanup_src_escrow<T>(escrow: EscrowSrc<T>) {
        let EscrowSrc { 
            id, 
            immutables: _, 
            token_balance, 
            sui_balance, 
            status: _, 
            merkle_info, 
        } = escrow;
        
        // Destroy empty balances
        destroy_zero(token_balance);
        destroy_zero(sui_balance);
        destroy_merkle_info(merkle_info);
        
        // Delete the object
        object::delete(id);
    }

    /// Clean up completed destination escrow
    public(package) fun cleanup_dst_escrow<T>(escrow: EscrowDst<T>) {
        let EscrowDst { 
            id, 
            immutables: _, 
            token_balance, 
            sui_balance, 
            status: _, 
            merkle_info 
        } = escrow;
        
        // Destroy empty balances
        destroy_zero(token_balance);
        destroy_zero(sui_balance);
        destroy_merkle_info(merkle_info);
        
        // Delete the object
        object::delete(id);
    }

    /// Consume and destroy MerkleSecretInfo explicitly.
    public(package) fun destroy_merkle_info(info: MerkleSecretInfo) {
    let MerkleSecretInfo {
        merkle_root: _,                    // ok to drop
        parts_amount:_,
        used_indices:_,          // vector by defauly 
    } = info;
    }



