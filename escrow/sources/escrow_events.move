/// Module: escrow
module escrow::events;
    
    use sui::event;

/// ---------------------------------------------------------------------------
/// EVENT STRUCTS
/// ---------------------------------------------------------------------------
/// All fields are plain, copy‑able primitives so this module has **no**
/// dependency on `escrow::structs`, avoiding cyclic‑import headaches.
/// ---------------------------------------------------------------------------

/// Fired when a maker finishes creating & sharing a pre‑funded wallet.
public struct WalletCreated has copy, drop, store {
    wallet_id: address,
    order_hash: vector<u8>,
    maker: address,
    initial_amount: u64,
    created_at: u64,
}

/// Fired when a resolver spins up a new source‑chain escrow.
public struct EscrowCreated has copy, drop, store {
    escrow_id: address,
    order_hash: vector<u8>,
    hashlock: vector<u8>,
    maker: address,
    taker: address,
    amount: u64,
    safety_deposit: u64,
    resolver: address,
    created_at: u64,
}

/// Fired when funds are successfully withdrawn (unlock or redeem).
public struct EscrowWithdrawn has copy, drop, store {
    escrow_id: address,
    order_hash: vector<u8>,
    secret: vector<u8>,
    withdrawn_by: address,
    maker: address,
    taker:address,
    amount: u64,
    withdrawn_at: u64,
}

/// Fired when an active escrow is cancelled and funds returned.
public struct EscrowCancelled has copy, drop, store {
    escrow_id: address,
    order_hash: vector<u8>,
    maker: address,
    taker: address,
    cancelled_by: address,
    amount: u64,
    cancelled_at: u64,
}

/// ---------------------------------------------------------------------------
/// EMITTER HELPERS
/// ---------------------------------------------------------------------------
/// These wrappers keep your main business‑logic modules tidy.  
/// Pass in primitives; the helper packs & emits the event.
/// ---------------------------------------------------------------------------

public fun wallet_created(
    wallet_id: address,
    order_hash: vector<u8>,
    maker: address,
    initial_amount: u64,
    created_at: u64,
) {
    event::emit<WalletCreated>(
        WalletCreated {
            wallet_id,
            order_hash,
            maker,
            initial_amount,
            created_at,
        },
    );
}

public fun escrow_created(
    escrow_id: address,
    order_hash: vector<u8>,
    hashlock: vector<u8>,
    taker: address,
    maker: address,
    amount: u64,
    safety_deposit: u64,
    resolver: address,
    created_at: u64,
) {
    event::emit<EscrowCreated>(
        EscrowCreated {
            escrow_id,
            order_hash,
            hashlock,
            maker,
            taker,
            amount,
            safety_deposit,
            resolver,
            created_at,
        },
    );
}

public fun escrow_withdrawn(
    escrow_id: address,
    order_hash: vector<u8>,
    secret: vector<u8>,
    withdrawn_by: address,
    maker: address,
    taker: address,
    amount: u64,
    withdrawn_at: u64,
) {
    event::emit<EscrowWithdrawn>(
        EscrowWithdrawn {
            escrow_id,
            order_hash,
            secret,
            withdrawn_by,
            maker,
            taker,
            amount,
            withdrawn_at,
        },
    );
}

public fun escrow_cancelled(
    escrow_id: address,
    order_hash: vector<u8>,
    maker: address,
    taker: address,
    cancelled_by: address,
    amount: u64,
    cancelled_at: u64
) {
    event::emit<EscrowCancelled>(
        EscrowCancelled {
            escrow_id,
            order_hash,
            maker,
            taker,
            cancelled_by,
            amount,
            cancelled_at,
        },
    );
}