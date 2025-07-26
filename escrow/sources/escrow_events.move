module escrow::events;

    use sui::event;

    // ============ Event Structs ============

    /// Emitted when a source escrow is created
    public struct EscrowSrcCreated has copy, drop {
        escrow_id: address,
        order_hash: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        is_merkle: bool,
        parts_amount: u8,
    }

    /// Emitted when a destination escrow is created
    public struct EscrowDstCreated has copy, drop {
        escrow_id: address,
        order_hash: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        src_cancellation_timestamp: u64,
        is_merkle: bool,
        parts_amount: u8,
    }

    /// Emitted when an escrow is withdrawn
    public struct EscrowWithdrawn has copy, drop {
        escrow_id: address,
        secret: vector<u8>,
        recipient: address,
        amount: u64,
        merkle_index: u64, // 0 if not merkle withdrawal
    }

    /// Emitted when an escrow is cancelled
    public struct EscrowCancelled has copy, drop {
        escrow_id: address,
        refund_to: address,
        amount: u64,
    }

    /// Emitted when funds are rescued
    public struct FundsRescued has copy, drop {
        escrow_id: address,
        rescuer: address,
        token_amount: u64,
        sui_amount: u64,
    }

    /// Emitted when access token is minted
    public struct AccessTokenMinted has copy, drop {
        recipient: address,
        token_id: address,
        created_at: u64,
    }

    // ============ Emit Functions ============

    public fun emit_escrow_src_created(
        escrow_id: address,
        order_hash: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        is_merkle: bool,
        parts_amount: u8,
    ) {
        event::emit(EscrowSrcCreated {
            escrow_id,
            order_hash,
            maker,
            taker,
            amount,
            safety_deposit,
            is_merkle,
            parts_amount,
        })
    }

    public fun emit_escrow_dst_created(
        escrow_id: address,
        order_hash: vector<u8>,
        maker: address,
        taker: address,
        amount: u64,
        safety_deposit: u64,
        src_cancellation_timestamp: u64,
        is_merkle: bool,
        parts_amount: u8,
    ) {
        event::emit(EscrowDstCreated {
            escrow_id,
            order_hash,
            maker,
            taker,
            amount,
            safety_deposit,
            src_cancellation_timestamp,
            is_merkle,
            parts_amount,
        })
    }