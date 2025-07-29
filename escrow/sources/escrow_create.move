/// Module: escrow
module escrow::escrow_create;

    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::clock::Clock;
    use std::string;
    use escrow::structs::{ Self, Wallet};
    use escrow::events;
    use escrow::utils;
    use escrow::constants::{
        e_invalid_amount,
        e_invalid_timelock,
        e_invalid_hashlock,
        e_invalid_order_hash,
        e_safety_deposit_too_low,
        min_safety_deposit,
    };

    // ============ Wallet Creation (Sui as Source) ============

    /// Create a pre-funded wallet for Sui->EVM swaps
    /// Maker deposits funds that resolvers can later use to create escrows
    /// @param order_hash - 32-byte unique order identifier
    /// @param funding - SUI coins to deposit in the wallet
    entry fun create_wallet(
        order_hash: vector<u8>,
        funding: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let maker = tx_context::sender(ctx);
        let initial_amount = coin::value(&funding);
        
        // Validate order hash
        assert!(vector::length(&order_hash) == 32, e_invalid_order_hash());
        assert!(initial_amount > 0, e_invalid_amount());
        
        // Create wallet with funding
        let wallet = structs::create_wallet(
            order_hash,
            maker,
            coin::into_balance(funding),
            sui::clock::timestamp_ms(clock),
            ctx,
        );
        
        // Get wallet address for event
        let wallet_address = structs::wallet_address(&wallet);
        
        // Emit creation event
        events::wallet_created(
            wallet_address,
            order_hash,
            maker,
            initial_amount,
            sui::clock::timestamp_ms(clock),
        );
        
        // Share the wallet object
        transfer::public_share_object(wallet);
    }

    // ============ Escrow Creation ============

    /// Create source chain escrow (Sui as source)
    /// Resolver pulls funds from pre-funded wallet
    /// @param wallet - Pre-funded wallet to pull funds from
    /// @param hashlock - 32-byte keccak256(secret) for this specific fill
    /// @param taker - Address receiving tokens on source chain
    /// @param amount - Amount of SUI to lock
    /// @param safety_deposit - Resolver's safety deposit
    /// @param src_withdrawal...dst_cancellation - Timelock timestamps (see guide above)
    entry fun create_escrow_src(
        wallet: &mut Wallet,
        hashlock: vector<u8>,
        taker: address,
        amount: u64,
        safety_deposit: Coin<SUI>,
        // Timelock parameters
        src_withdrawal: u64,
        src_public_withdrawal: u64,
        src_cancellation: u64,
        src_public_cancellation: u64,
        dst_withdrawal: u64,
        dst_public_withdrawal: u64,
        dst_cancellation: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let resolver = tx_context::sender(ctx);
        let safety_deposit_amount = coin::value(&safety_deposit);
        
        // Create timelocks struct
        let timelocks = structs::create_timelocks(
            sui::clock::timestamp_ms(clock), // deployed_at
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            src_public_cancellation,
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
        );
        
        // Validate inputs
        assert!(amount > 0, e_invalid_amount());
        assert!(safety_deposit_amount >= min_safety_deposit(), e_safety_deposit_too_low());
        assert!(vector::length(&hashlock) == 32, e_invalid_hashlock());
        assert!(utils::is_valid_timelocks(&timelocks), e_invalid_timelock());
        
        // Pull funds from wallet
        let token_balance = structs::withdraw_from_wallet_for_escrow(wallet, amount);
        
        // Create immutables
        let immutables = structs::create_escrow_immutables(
            *structs::wallet_order_hash(wallet),
            hashlock,
            structs::wallet_maker(wallet),
            taker,
            string::utf8(b"SUI"),
            amount,
            safety_deposit_amount,
            resolver,
            timelocks,
        );
        
        // Validate immutables
        assert!(utils::validate_immutables(&immutables), e_invalid_amount());
        
        // Create escrow
        let escrow = structs::create_escrow_src<SUI>(
            immutables,
            token_balance,
            coin::into_balance(safety_deposit),
            ctx,
        );
        
        // Get escrow address for event
        let escrow_address = structs::get_src_address(&escrow);
        
        // Emit creation event
        events::escrow_created(
            escrow_address,
            *structs::wallet_order_hash(wallet),
            hashlock,
            taker,
            structs::wallet_maker(wallet),
            amount,
            safety_deposit_amount,
            resolver,
            sui::clock::timestamp_ms(clock),
        );
        
        // Share the escrow
        transfer::public_share_object(escrow);
    }

    /// Create destination chain escrow (Sui as destination)
    /// Taker deposits funds directly
    /// @param order_hash - 32-byte unique order identifier
    /// @param hashlock - 32-byte keccak256(secret) for this specific fill
    /// @param maker - Address receiving tokens on destination chain
    /// @param token_deposit - SUI tokens to lock
    /// @param safety_deposit - Taker's safety deposit (taker acts as resolver)
    /// @param src_withdrawal...dst_cancellation - Timelock timestamps (see guide above)
    entry fun create_escrow_dst(
        order_hash: vector<u8>,
        hashlock: vector<u8>,
        maker: address,
        token_deposit: Coin<SUI>,
        safety_deposit: Coin<SUI>,
        // Timelock parameters
        src_withdrawal: u64,
        src_public_withdrawal: u64,
        src_cancellation: u64,
        src_public_cancellation: u64,
        dst_withdrawal: u64,
        dst_public_withdrawal: u64,
        dst_cancellation: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let taker = tx_context::sender(ctx);
        let resolver = tx_context::sender(ctx); // In dst escrow, taker acts as resolver
        let amount = coin::value(&token_deposit);
        let safety_deposit_amount = coin::value(&safety_deposit);
        
        // Create timelocks struct
        let timelocks = structs::create_timelocks(
            sui::clock::timestamp_ms(clock), // deployed_at
            src_withdrawal,
            src_public_withdrawal,
            src_cancellation,
            src_public_cancellation,
            dst_withdrawal,
            dst_public_withdrawal,
            dst_cancellation,
        );
        
        // Validate inputs
        assert!(amount > 0, e_invalid_amount());
        assert!(safety_deposit_amount >= min_safety_deposit(), e_safety_deposit_too_low());
        assert!(vector::length(&order_hash) == 32, e_invalid_hashlock());
        assert!(vector::length(&hashlock) == 32, e_invalid_hashlock());
        assert!(utils::is_valid_timelocks(&timelocks), e_invalid_timelock());
        
        // Create immutables
        let immutables = structs::create_escrow_immutables(
            order_hash,
            hashlock,
            maker,
            taker,
            string::utf8(b"SUI"),
            amount,
            safety_deposit_amount,
            resolver,
            timelocks,
        );
        
        // Validate immutables
        assert!(utils::validate_immutables(&immutables), e_invalid_amount());
        
        // Create escrow
        let escrow = structs::create_escrow_dst<SUI>(
            immutables,
            coin::into_balance(token_deposit),
            coin::into_balance(safety_deposit),
            ctx,
        );
        
        // Get escrow address for event
        let escrow_address = structs::get_dst_address(&escrow);
        
        // Emit creation event
        events::escrow_created(
            escrow_address,
            order_hash,
            hashlock,
            taker,
            maker,
            amount,
            safety_deposit_amount,
            resolver,
            sui::clock::timestamp_ms(clock),
        );
        
        // Share the escrow
        transfer::public_share_object(escrow);
    }
