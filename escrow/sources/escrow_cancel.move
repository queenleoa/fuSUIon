/// Module: escrow
module escrow::escrow_cancel;

    use sui::sui::SUI;
    use sui::coin::{Self};
    use sui::clock::Clock;
    use escrow::structs::{Self, EscrowSrc, EscrowDst};
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

    // ============ Cancellation Functions ============
// Note: Status must be updated before extracting balances to avoid 
// multiple mutable borrows of the escrow object

/// Cancel source escrow (refund to maker)
entry fun cancel_src(
    escrow: &mut EscrowSrc<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let caller = tx_context::sender(ctx);
    let immutables = structs::get_src_immutables(escrow);
    let timelocks = structs::get_timelocks(immutables);
    let current_stage = utils::src_stage(timelocks, clock);
    
    // Check status
    assert!(structs::get_src_status(escrow) == status_active(), e_already_cancelled());
   
    // Check cancellation permissions based on stage
    if (current_stage == stage_resolver_exclusive_cancel()) {
        // Only assigned resolver can cancel
        assert!(caller == structs::get_resolver(immutables), e_unauthorised());
    } else if (current_stage == stage_public_cancel()) {
        // Anyone can cancel (public phase)
        // No specific authorization needed
    } else {
        abort e_not_cancellable()
    };

    // Extract balances after status update
    let token_balance = structs::extract_src_tokens(escrow);
    let safety_deposit = structs::extract_src_safety_deposit(escrow);
    
    // Update status first (before extracting balances)
    structs::set_src_status(escrow, status_cancelled());
    
    // Return tokens to maker
    let maker = structs::get_maker(immutables);
    transfer::public_transfer(coin::from_balance(token_balance, ctx), maker);
    
    // Send safety deposit to cancelling resolver
    transfer::public_transfer(coin::from_balance(safety_deposit, ctx), caller);
    
    // Emit cancellation event
    events::escrow_cancelled(
        structs::get_src_address(escrow),
        *structs::get_order_hash(immutables),
        structs::get_maker(immutables),
        structs::get_taker(immutables),
        caller,
        structs::get_amount(immutables),
        sui::clock::timestamp_ms(clock),
    );
}

/// Cancel destination escrow (refund to taker)
entry fun cancel_dst(
    escrow: &mut EscrowDst<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let caller = tx_context::sender(ctx);
    let immutables = structs::get_dst_immutables(escrow);
    let timelocks = structs::get_timelocks(immutables);
    let current_stage = utils::dst_stage(timelocks, clock);
    
    // Check status
    assert!(structs::get_dst_status(escrow) == status_active(), e_already_cancelled());
    
    // Check if we're past cancellation deadline
    assert!(current_stage >= stage_resolver_exclusive_cancel(), e_not_cancellable());
    
    // Only resolver can cancel dst escrow
    assert!(caller == structs::get_resolver(immutables), e_unauthorised());
    
    // Extract balances after status update
    let token_balance = structs::extract_src_tokens(escrow);
    let safety_deposit = structs::extract_src_safety_deposit(escrow);
    
    // Return tokens to taker
    let taker = structs::get_taker(immutables);
    transfer::public_transfer(coin::from_balance(token_balance, ctx), taker);
    
    // Send safety deposit to cancelling resolver
    transfer::public_transfer(coin::from_balance(safety_deposit, ctx), caller);
    
    // Emit cancellation event
    events::escrow_cancelled(
        structs::get_dst_address(escrow),
        *structs::get_order_hash(immutables),
        structs::get_maker(immutables),
        structs::get_taker(immutables),
        caller,
        structs::get_amount(immutables),
        sui::clock::timestamp_ms(clock),
    );
}
