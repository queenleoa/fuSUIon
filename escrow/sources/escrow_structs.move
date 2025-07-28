/// Module: escrow
module escrow::structs;

    use std::string::String;
    use sui::balance::{Balance, withdraw_all, destroy_zero, value};
    use sui::sui::SUI;
    use escrow::constants::{status_active};
    use sui::clock::{Clock, timestamp_ms};

// ============ Core Structs ============

    /// Core immutable parameters for escrow operations
    public struct EscrowImmutables has copy, drop, store {
        order_hash: vector<u8>,      // 32 bytes - unique identifier for the order
        hashlock: vector<u8>,        // 32 bytes - keccak256(secret) for the specific fill
        maker: address,              // Address that provides source tokens
        taker: address,              // Address that provides destination tokens
        token_type: String,          // Token type identifier (for generic token support)
        amount: u64,                 // Amount of tokens to be swapped
        safety_deposit_amount: u64,         // Safety deposit amount in SUI (paid by resolver)
        resolver: address,           // Address of the resolver handling this escrow
        timelocks: Timelocks,       // Timelock configuration
    }

    /// Timelocks configuration
    public struct Timelocks has copy, drop, store {
        deployed_at: u64,
        src_withdrawal: u64,
        src_public_withdrawal: u64,
        src_cancellation: u64,
        src_public_cancellation: u64,
        dst_withdrawal: u64,
        dst_public_withdrawal: u64,
        dst_cancellation: u64,
    }

    /// Source chain escrow object - holds maker's tokens
    /// Must be a shared object for cross-party access
    public struct EscrowSrc<phantom T> has key, store {
        id: UID,
        immutables: EscrowImmutables,
        token_balance: Balance<T>,           // Maker's locked tokens
        safety_deposit: Balance<SUI>,        // Resolver's safety deposit
        status: u8,                          // Current status (active/withdrawn/cancelled)
    }

    /// Destination chain escrow object - ensure SHARED for consensus
    /// holds taker tokens
    public struct EscrowDst<phantom T> has key, store {
        id: UID,
        immutables: EscrowImmutables,
        token_balance: Balance<T>,           // Taker's locked tokens
        safety_deposit: Balance<SUI>,        // Resolver's safety deposit
        status: u8,                          // Current status (active/withdrawn/cancelled)
    }

    /// Represents the state of an order across all fills
    /// Created by relayer when order is placed
    public struct OrderState has key, store {
        id: UID,
        order_hash: vector<u8>,              // 32 bytes - order identifier
        merkle_root: vector<u8>,             // 32 bytes - merkle tree root
        total_amount: u64,                   // Total order amount
        filled_amount: u64,                  // Amount filled so far
        parts_amount: u8,                    // Total number of parts (N)
        used_indices: vector<u8>,            // Indices that have been used
        resolver_fills: vector<ResolverFill>, // Track fills by each resolver
    }

    /// Track individual resolver fills for an order
    public struct ResolverFill has store {
        resolver: address,
        filled_amount: u64,
        indices_used: vector<u8>,
        timestamp: u64,
    }

    /// Access token for resolver authorization
    public struct AccessToken has key, store {
        id: UID,
        resolver: address,                   // Resolver this token is minted for
        minted_at: u64,                     // When the token was minted
        expires_at: u64,                    // When the token expires
    }

    /// User intent for authorizing resolver actions
    public struct UserIntent has drop {
        order_hash: vector<u8>,
        resolver: address,
        action: u8,                         // 0: create, 1: cancel
        verified_at: u64,
        expiry: u64,
        nonce: u64,
    }

    // ============ Getter Functions ============

    // EscrowImmutables getters
    public(package) fun get_order_hash(immutables: &EscrowImmutables): &vector<u8> { &immutables.order_hash }
    public(package) fun get_hashlock(immutables: &EscrowImmutables): &vector<u8> { &immutables.hashlock }
    public(package) fun get_maker(immutables: &EscrowImmutables): address { immutables.maker }
    public(package) fun get_taker(immutables: &EscrowImmutables): address { immutables.taker }
    public(package) fun get_token_type(immutables: &EscrowImmutables): &String { &immutables.token_type }
    public(package) fun get_amount(immutables: &EscrowImmutables): u64 { immutables.amount }
    public(package) fun get_safety_deposit_amount(immutables: &EscrowImmutables): u64 { immutables.safety_deposit_amount }
    public(package) fun get_resolver(immutables: &EscrowImmutables): address { immutables.resolver }
    public(package) fun get_timelocks(immutables: &EscrowImmutables): &Timelocks { &immutables.timelocks }

    // Timelocks getters
    public(package) fun get_deployed_at(timelocks: &Timelocks): u64 { timelocks.deployed_at }
    public(package) fun get_src_withdrawal_time(timelocks: &Timelocks): u64 { timelocks.src_withdrawal }
    public(package) fun get_src_public_withdrawal_time(timelocks: &Timelocks): u64 { timelocks.src_public_withdrawal }
    public(package) fun get_src_cancellation_time(timelocks: &Timelocks): u64 { timelocks.src_cancellation }
    public(package) fun get_src_public_cancellation_time(timelocks: &Timelocks): u64 { timelocks.src_public_cancellation }
    public(package) fun get_dst_withdrawal_time(timelocks: &Timelocks): u64 { timelocks.dst_withdrawal }
    public(package) fun get_dst_public_withdrawal_time(timelocks: &Timelocks): u64 { timelocks.dst_public_withdrawal }
    public(package) fun get_dst_cancellation_time(timelocks: &Timelocks): u64 { timelocks.dst_cancellation }

    // EscrowSrc getters
    public(package) fun get_src_address<T>(escrow: &EscrowSrc<T>): address { object::uid_to_address(&escrow.id) }
    public(package) fun get_src_immutables<T>(escrow: &EscrowSrc<T>): &EscrowImmutables { &escrow.immutables }
    public(package) fun get_src_token_balance<T>(escrow: &EscrowSrc<T>): u64 { value(&escrow.token_balance) }
    public(package) fun get_src_safety_deposit<T>(escrow: &EscrowSrc<T>): u64 { value(&escrow.safety_deposit) }
    public(package) fun get_src_status<T>(escrow: &EscrowSrc<T>): u8 { escrow.status }

    // EscrowDst getters
    public(package) fun get_dst_address<T>(escrow: &EscrowDst<T>): address { object::uid_to_address(&escrow.id) }
    public(package) fun get_dst_immutables<T>(escrow: &EscrowDst<T>): &EscrowImmutables { &escrow.immutables }
    public(package) fun get_dst_token_balance<T>(escrow: &EscrowDst<T>): u64 { value(&escrow.token_balance) }
    public(package) fun get_dst_safety_deposit<T>(escrow: &EscrowDst<T>): u64 { value(&escrow.safety_deposit) }
    public(package) fun get_dst_status<T>(escrow: &EscrowDst<T>): u8 { escrow.status }


    // OrderState getters
    public(package) fun get_order_state_address(state: &OrderState): address { object::uid_to_address(&state.id) }
    public(package) fun get_order_state_order_hash(state: &OrderState): &vector<u8> { &state.order_hash }
    public(package) fun get_order_state_merkle_root(state: &OrderState): &vector<u8> { &state.merkle_root }
    public(package) fun get_order_state_total_amount(state: &OrderState): u64 { state.total_amount }
    public(package) fun get_order_state_filled_amount(state: &OrderState): u64 { state.filled_amount }
    public(package) fun get_order_state_parts_amount(state: &OrderState): u8 { state.parts_amount }
    public(package) fun get_order_state_used_indices(state: &OrderState): &vector<u8> { &state.used_indices }
    public(package) fun get_order_state_resolver_fills(state: &OrderState): &vector<ResolverFill> { &state.resolver_fills }

    // AccessToken getters
    public(package) fun get_token_address(token: &AccessToken): address { object::uid_to_address(&token.id) }
    public(package) fun get_token_resolver(token: &AccessToken): address { token.resolver }
    public(package) fun get_token_minted_at(token: &AccessToken): u64 { token.minted_at }
    public(package) fun get_token_expires_at(token: &AccessToken): u64 { token.expires_at }

    // ============ Setter/Mutator Functions ============

    // Escrow status mutators
    public(package) fun set_src_status<T>(escrow: &mut EscrowSrc<T>, status: u8) {
        escrow.status = status;
    }

    public(package) fun set_dst_status<T>(escrow: &mut EscrowDst<T>, status: u8) {
        escrow.status = status;
    }

    // OrderState mutators
    public(package) fun update_order_state_filled_amount(state: &mut OrderState, amount: u64) {
        state.filled_amount = state.filled_amount + amount;
    }

    public(package) fun add_order_state_used_index(state: &mut OrderState, index: u8) {
        vector::push_back(&mut state.used_indices, index);
    }

    public(package) fun add_order_state_resolver_fill(state: &mut OrderState, fill: ResolverFill) {
        vector::push_back(&mut state.resolver_fills, fill);
    }

    // ============ Balance Operations ============

    // Extract balances for withdrawals
    public(package) fun extract_src_tokens<T>(escrow: &mut EscrowSrc<T>): Balance<T> {
        withdraw_all(&mut escrow.token_balance)
    }

    public(package) fun extract_src_safety_deposit<T>(escrow: &mut EscrowSrc<T>): Balance<SUI> {
        withdraw_all(&mut escrow.safety_deposit)
    }

    public(package) fun extract_dst_tokens<T>(escrow: &mut EscrowDst<T>): Balance<T> {
        withdraw_all(&mut escrow.token_balance)
    }

    public(package) fun extract_dst_safety_deposit<T>(escrow: &mut EscrowDst<T>): Balance<SUI> {
        withdraw_all(&mut escrow.safety_deposit)
    }

    // ============ Constructor Functions for Keyed Structs ============

    /// Create a new EscrowSrc object
    public(package) fun create_escrow_src<T>(
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        safety_deposit: Balance<SUI>,
        ctx: &mut TxContext,
    ): EscrowSrc<T> {
        EscrowSrc {
            id: object::new(ctx),
            immutables,
            token_balance,
            safety_deposit,
            status: status_active(),
        }
    }

    /// Create a new EscrowDst object
    public(package) fun create_escrow_dst<T>(
        immutables: EscrowImmutables,
        token_balance: Balance<T>,
        safety_deposit: Balance<SUI>,
        ctx: &mut TxContext,
    ): EscrowDst<T> {
        EscrowDst {
            id: object::new(ctx),
            immutables,
            token_balance,
            safety_deposit,
            status: status_active(),
        }
    }

    /// Create a new OrderState object
    public(package) fun create_order_state(
        order_hash: vector<u8>,
        merkle_root: vector<u8>,
        total_amount: u64,
        parts_amount: u8,
        ctx: &mut TxContext,
    ): OrderState {
        OrderState {
            id: object::new(ctx),
            order_hash,
            merkle_root,
            total_amount,
            filled_amount: 0,
            parts_amount,
            used_indices: vector::empty(),
            resolver_fills: vector::empty(),
        }
    }

    /// Create a new AccessToken object
    public(package) fun create_access_token(
        resolver: address,
        validity_period: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ): AccessToken {
        let current_time = timestamp_ms(clock) / 1000;
        AccessToken {
            id: object::new(ctx),
            resolver,
            minted_at: current_time,
            expires_at: current_time + validity_period,
        }
    }

    /// Create a new UserIntent
    public(package) fun create_user_intent(
        order_hash: vector<u8>,
        resolver: address,
        action: u8,                         // 0: create, 1: cancel
        verified_at: u64,
        expiry: u64,
        nonce: u64,
    ): UserIntent {
        UserIntent{
        order_hash: order_hash,
        resolver: resolver,
        action: action,                         // 0: create, 1: cancel
        verified_at: verified_at,
        expiry: expiry,
        nonce: nonce,
        }
    }

    // ============ Constructor Functions ============

    public(package) fun create_escrow_immutables(
        order_hash: vector<u8>,
        hashlock: vector<u8>,
        maker: address,
        taker: address,
        token_type: String,
        amount: u64,
        safety_deposit_amount: u64,
        resolver: address,
        timelocks: Timelocks,
    ): EscrowImmutables {
        EscrowImmutables {
            order_hash,
            hashlock,
            maker,
            taker,
            token_type,
            amount,
            safety_deposit_amount,
            resolver,
            timelocks,
        }
    }

    public(package) fun create_timelocks(
        deployed_at: u64,
        src_withdrawal: u64,
        src_public_withdrawal: u64,
        src_cancellation: u64,
        src_public_cancellation: u64,
        dst_withdrawal: u64,
        dst_public_withdrawal: u64,
        dst_cancellation: u64,
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

    public(package) fun create_resolver_fill(
        resolver: address,
        filled_amount: u64,
        indices_used: vector<u8>,
        timestamp: u64,
    ): ResolverFill {
        ResolverFill {
            resolver,
            filled_amount,
            indices_used,
            timestamp,
        }
    }

    // ============ Object Cleanup Functions ============

    /// Destroy EscrowSrc after lifecycle is complete
    public(package) fun destroy_src_escrow<T>(escrow: EscrowSrc<T>) {
        let EscrowSrc { 
            id, 
            immutables: _, 
            token_balance, 
            safety_deposit, 
            status: _
        } = escrow;
        
        destroy_zero(token_balance);
        destroy_zero(safety_deposit);
        object::delete(id);
    }

    /// Destroy EscrowDst after lifecycle is complete
    public(package) fun destroy_dst_escrow<T>(escrow: EscrowDst<T>) {
        let EscrowDst { 
            id, 
            immutables: _, 
            token_balance, 
            safety_deposit, 
            status: _
        } = escrow;
        
        destroy_zero(token_balance);
        destroy_zero(safety_deposit);
        object::delete(id);
    }

    /// Destroy OrderState after all fills are complete
    public(package) fun destroy_order_state(state: OrderState) {
        let OrderState { 
            id, 
            order_hash: _, 
            merkle_root: _, 
            total_amount: _, 
            filled_amount: _, 
            parts_amount: _,
            used_indices: _,
            resolver_fills, 
        } = state;

        let mut fills = resolver_fills;
        while (!vector::is_empty(&fills)) {
        let resolver_fill = vector::pop_back(&mut fills);
        destroy_resolver_fill(resolver_fill);
        };
        vector::destroy_empty(fills);
        object::delete(id);
    }

    fun destroy_resolver_fill(resolver_fill: ResolverFill) {
        let ResolverFill {
            resolver: _,
            filled_amount: _,
            indices_used: _, // vector<u8> has drop
            timestamp: _,
        } = resolver_fill;
    }

    /// Destroy expired AccessToken
    public(package) fun destroy_access_token(token: AccessToken) {
        let AccessToken { 
            id, 
            resolver: _, 
            minted_at: _, 
            expires_at: _
        } = token;
        
        object::delete(id);
    }



