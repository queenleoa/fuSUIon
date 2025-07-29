/// Module: escrow
module escrow::structs;

    use std::string::String;
    use sui::balance::{Balance, withdraw_all, split, destroy_zero, value};
    use sui::sui::SUI;
    use escrow::constants::{status_active, e_insufficient_balance, e_wallet_inactive};
   

// ======== Wallet (Sui as source chain) ========
    // Design rationale: wallet is a pre-funded wallet that makers create
    // Resolvers can pull funds from this wallet to create escrows
    // This enables partial fills - multiple resolvers can create escrows from one wallet
    // The wallet itself is NOT the escrow - it's just a funding source
    public struct Wallet has key {
        id: UID,
        order_hash: vector<u8>,
        maker: address,
        initial_amount: u64,
        balance: Balance<SUI>,
        created_at: u64,
        is_active: bool
    }


// ============ Core Structs ============

    /// Core immutable parameters for escrow operations
    public struct EscrowImmutables has copy, drop, store {
        order_hash: vector<u8>,      // 32 bytes - unique identifier for the order
        hashlock: vector<u8>,        // 32 bytes - keccak256(secret) for the specific fill
        maker: address,              // Address that provides source tokens
        taker: address,              // Address that provides destination tokens
        token_type: String,          // Token type identifier (for generic token support). Using SUI
        amount: u64,                 // Amount of tokens to be swapped
        safety_deposit_amount: u64,  // Safety deposit amount in SUI (paid by resolver)
        resolver: address,           // Address of the resolver handling this escrow
        timelocks: Timelocks,        // Timelock configuration
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
        token_balance: Balance<SUI>,         // Maker's locked tokens (only SUI)
        safety_deposit: Balance<SUI>,        // Resolver's safety deposit
        status: u8,                          // Current status (active/withdrawn/cancelled)
    }

    /// Destination chain escrow object - ensure SHARED for consensus
    /// holds taker tokens
    public struct EscrowDst<phantom T> has key, store {
        id: UID,
        immutables: EscrowImmutables,
        token_balance: Balance<SUI>,         // Taker's locked tokens (only SUI)
        safety_deposit: Balance<SUI>,        // Resolver's safety deposit
        status: u8,                          // Current status (active/withdrawn/cancelled)
    }

    // ============ Getter Functions ============

    // Wallet getters
    public(package) fun wallet_id(wallet: &Wallet): &UID { &wallet.id }
    public(package) fun wallet_address(wallet: &Wallet): address {object::uid_to_address(&wallet.id) }
    public(package) fun wallet_order_hash(wallet: &Wallet): &vector<u8> { &wallet.order_hash }
    public(package) fun wallet_maker(wallet: &Wallet): address { wallet.maker }
    public(package) fun wallet_initial_amount(wallet: &Wallet): u64 { wallet.initial_amount }
    public(package) fun wallet_balance(wallet: &Wallet): u64 { value(&wallet.balance) }
    public(package) fun wallet_created_at(wallet: &Wallet): u64 { wallet.created_at }
    public(package) fun wallet_is_active(wallet: &Wallet): bool { wallet.is_active }

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
    public(package) fun get_src_id<T>(escrow: &EscrowSrc<T>): &UID { &escrow.id}
    public(package) fun get_src_address<T>(escrow: &EscrowSrc<T>): address { object::uid_to_address(&escrow.id) } //for logs
    public(package) fun get_src_immutables<T>(escrow: &EscrowSrc<T>): &EscrowImmutables { &escrow.immutables }
    public(package) fun get_src_token_balance<T>(escrow: &EscrowSrc<T>): u64 { value(&escrow.token_balance) }
    public(package) fun get_src_safety_deposit<T>(escrow: &EscrowSrc<T>): u64 { value(&escrow.safety_deposit) }
    public(package) fun get_src_status<T>(escrow: &EscrowSrc<T>): u8 { escrow.status }

    // EscrowDst getters
    public(package) fun get_dst_id<T>(escrow: &EscrowSrc<T>): &UID { &escrow.id}
    public(package) fun get_dst_address<T>(escrow: &EscrowDst<T>): address { object::uid_to_address(&escrow.id) } //for logs
    public(package) fun get_dst_immutables<T>(escrow: &EscrowDst<T>): &EscrowImmutables { &escrow.immutables }
    public(package) fun get_dst_token_balance<T>(escrow: &EscrowDst<T>): u64 { value(&escrow.token_balance) }
    public(package) fun get_dst_safety_deposit<T>(escrow: &EscrowDst<T>): u64 { value(&escrow.safety_deposit) }
    public(package) fun get_dst_status<T>(escrow: &EscrowDst<T>): u8 { escrow.status }

    // ============ Setter/Mutator Functions ============

    // Escrow status mutators
    public(package) fun set_src_status<T>(escrow: &mut EscrowSrc<T>, status: u8) {
        escrow.status = status;
    }

    public(package) fun set_dst_status<T>(escrow: &mut EscrowDst<T>, status: u8) {
        escrow.status = status;
    }


    // ============ Balance Operations for escrows ============

    // Extract balances for withdrawals
    public(package) fun extract_src_tokens<T>(escrow: &mut EscrowSrc<T>): Balance<SUI> {
        withdraw_all(&mut escrow.token_balance)
    }

    public(package) fun extract_src_safety_deposit<T>(escrow: &mut EscrowSrc<T>): Balance<SUI> {
        withdraw_all(&mut escrow.safety_deposit)
    }

    public(package) fun extract_dst_tokens<T>(escrow: &mut EscrowDst<T>): Balance<SUI> {
        withdraw_all(&mut escrow.token_balance)
    }

    public(package) fun extract_dst_safety_deposit<T>(escrow: &mut EscrowDst<T>): Balance<SUI> {
        withdraw_all(&mut escrow.safety_deposit)
    }

    // ============ Constructor Functions for Keyed Structs ============

    /// Create a new Wallet. Entry Fn. Call using PTB
    public(package) fun create_wallet (
        order_hash: vector<u8>,
        maker: address,
        initial_balance: Balance<SUI>,
        created_at: u64,
        ctx: &mut TxContext,
    ): Wallet {
        Wallet {
            id: object::new(ctx),
            order_hash: order_hash,
            maker: maker,
            initial_amount: value(&initial_balance),
            balance: initial_balance,
            created_at: created_at,
            is_active: true,
        }
    }

    /// Create a new EscrowSrc object
    public(package) fun create_escrow_src<T>(
        immutables: EscrowImmutables,
        token_balance: Balance<SUI>,
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
        token_balance: Balance<SUI>,
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

    // ============ Other Constructor Functions ============

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

    // Withdraws funds from wallet to create an escrow
    // Returns the balance for the wallet
    public(package) fun withdraw_from_wallet_for_escrow(
    wallet: &mut Wallet,
    escrow_amount: u64,
    ): Balance<SUI> {
        // 1. Wallet must still be usable
        assert!(wallet.is_active, e_wallet_inactive());

        // 2. Must hold enough SUI
        assert!(
            value(&wallet.balance) >= escrow_amount,
            e_insufficient_balance()
        );
        //    `balance::split` :: (&mut Balance<T>, u64) -> Balance<T>
        //    ‑ moves the requested amount into a *new* Balance<T> and shrinks the
        //      original in‑place.
        split(&mut wallet.balance, escrow_amount)
    }
    
    // Return unused funds to maker when wallet is closed
    public(package) fun close_vault(wallet: &mut Wallet): Balance<SUI> {
        wallet.is_active = false;
        withdraw_all(&mut wallet.balance)
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

    