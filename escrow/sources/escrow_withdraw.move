/// Module: escrow
module escrow::escrow_withdraw;

    use sui::sui::SUI;
    use sui::coin::{Self};
    use sui::clock::Clock;
    use escrow::structs::{Self, Wallet, EscrowSrc, EscrowDst, EscrowImmutables, Timelocks};
    use escrow::events;
    use escrow::utils;
    use escrow::constants::{
        e_invalid_amount,
        e_invalid_timelock,
        e_invalid_hashlock,
        e_invalid_order_hash,
        e_invalid_secret,
        e_unauthorised,
        e_already_withdrawn,
        e_not_withdrawable,
        e_already_cancelled,
        e_not_cancellable,
        e_safety_deposit_too_low,
        min_safety_deposit,
        status_active,
        status_withdrawn,
        status_cancelled,
        stage_resolver_exclusive_withdraw,
        stage_public_withdraw,
        stage_resolver_exclusive_cancel,
        stage_public_cancel,
    };

    // ============ Withdrawal Functions ============

    /// Withdraw from source escrow (reveal secret, funds go to taker)
    entry fun withdraw_src(
        escrow: &mut EscrowSrc<SUI>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let caller = tx_context::sender(ctx);
        let immutables = structs::get_src_immutables(escrow);
        let timelocks = structs::get_timelocks(immutables);
        let current_stage = utils::src_stage(timelocks, clock);
        
        // Check status
        assert!(structs::get_src_status(escrow) == status_active(), e_already_withdrawn());
        
        // Validate secret
        assert!(utils::validate_secret_length(&secret), e_invalid_secret());
        assert!(utils::validate_hashlock(&secret, structs::get_hashlock(immutables)), e_invalid_secret());
        
        // Check withdrawal permissions based on stage
        if (current_stage == stage_resolver_exclusive_withdraw()) {
            // Only assigned resolver can withdraw
            assert!(caller == structs::get_resolver(immutables), e_unauthorised());
        } else if (current_stage == stage_public_withdraw()) {
            // Any resolver can withdraw (public phase)
            // No specific authorization needed
        } else {
            abort e_not_withdrawable()
        };
        
        // Extract balances
        let token_balance = structs::extract_src_tokens(escrow);
        let safety_deposit = structs::extract_src_safety_deposit(escrow);
        
        // Update status
        structs::set_src_status(escrow, status_withdrawn());
        
        // Send tokens to taker
        let taker = structs::get_taker(immutables);
        transfer::public_transfer(coin::from_balance(token_balance, ctx), taker);
        
        // Send safety deposit to withdrawing resolver
        transfer::public_transfer(coin::from_balance(safety_deposit, ctx), caller);
        
        // Emit withdrawal event
        events::escrow_withdrawn(
            structs::get_src_address(escrow),
            *structs::get_order_hash(immutables),
            secret,
            caller,
            structs::get_maker(immutables),
            structs::get_taker(immutables),
            structs::get_amount(immutables),
            sui::clock::timestamp_ms(clock),
        );
    }

    /// Withdraw from destination escrow (reveal secret, funds go to maker)
    entry fun withdraw_dst(
        escrow: &mut EscrowDst<SUI>,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let caller = tx_context::sender(ctx);
        let immutables = structs::get_dst_immutables(escrow);
        let timelocks = structs::get_timelocks(immutables);
        let current_stage = utils::dst_stage(timelocks, clock);
        
        // Check status
        assert!(structs::get_dst_status(escrow) == status_active(), e_already_withdrawn());
        
        // Validate secret
        assert!(utils::validate_secret_length(&secret), e_invalid_secret());
        assert!(utils::validate_hashlock(&secret, structs::get_hashlock(immutables)), e_invalid_secret());
        
        // Check withdrawal permissions based on stage
        if (current_stage == stage_resolver_exclusive_withdraw()) {
            // Only assigned resolver can withdraw
            assert!(caller == structs::get_resolver(immutables), e_unauthorised());
        } else if (current_stage == stage_public_withdraw()) {
            // Any resolver can withdraw (public phase)
            // No specific authorization needed
        } else {
            abort e_not_withdrawable()
        };
        
        // Extract balances
        let token_balance = structs::extract_dst_tokens(escrow);
        let safety_deposit = structs::extract_dst_safety_deposit(escrow);
        
        // Update status
        structs::set_dst_status(escrow, status_withdrawn());
        
        // Send tokens to maker
        let maker = structs::get_maker(immutables);
        transfer::public_transfer(coin::from_balance(token_balance, ctx), maker);
        
        // Send safety deposit to withdrawing resolver
        transfer::public_transfer(coin::from_balance(safety_deposit, ctx), caller);
        
        // Emit withdrawal event
        events::escrow_withdrawn(
            structs::get_dst_address(escrow),
            *structs::get_order_hash(immutables),
            secret,
            caller,
            structs::get_maker(immutables),
            structs::get_taker(immutables),
            structs::get_amount(immutables),
            sui::clock::timestamp_ms(clock),
        );
    }