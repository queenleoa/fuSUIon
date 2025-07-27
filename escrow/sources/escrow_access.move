/// Module: escrow
module escrow::escrow_access;

    use sui::clock::Clock;
    use escrow::constants::{
        default_rescue_delay,
        error_invalid_caller,
        };
    use escrow::structs::{
        new_access_token,
        get_access_token_address
        };
    use escrow::events;

    // ============ Factory Struct ============

    /// Global configuration object
    public struct Factory has key {
        id: UID,
        rescue_delay: u64,
        access_token_supply: u64,
        admin: address,
    }

    // ============ Init Function ============

    fun init(ctx: &mut TxContext) {
        let factory = Factory {
            id: object::new(ctx),
            rescue_delay: default_rescue_delay(),
            access_token_supply: 0,
            admin: tx_context::sender(ctx),
        };
        
        // Share the factory object for global access
        transfer::share_object(factory);
    }

    // ============ Access Token Management ============

    /// Mint a new access token for public operations (admin only)
    public fun mint_access_token(
        factory: &mut Factory,
        recipient: address,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Only admin can mint access tokens
        assert!(
            tx_context::sender(ctx) == factory.admin,
            error_invalid_caller()
        );
        
        let token = new_access_token(
            sui::clock::timestamp_ms(clock) / 1000,
            ctx
        );

        let token_id = get_access_token_address(&token);
        
        // Increment supply counter
        factory.access_token_supply = factory.access_token_supply + 1;

        // Emit event
        events::emit_access_token_minted(
            recipient,
            token_id,
            sui::clock::timestamp_ms(clock) / 1000,
        );

        // Transfer to recipient
        transfer::public_transfer(token, recipient);
    }

    // ============ Admin Functions ============

    /// Update rescue delay (admin only)
    public fun update_rescue_delay(
        factory: &mut Factory,
        new_delay: u64,
        ctx: &mut TxContext
    ) {
        assert!(
            tx_context::sender(ctx) == factory.admin,
            error_invalid_caller()
        );
        factory.rescue_delay = new_delay;
    }

    /// Transfer admin role
    public fun transfer_admin(
        factory: &mut Factory,
        new_admin: address,
        ctx: &mut TxContext
    ) {
        assert!(
            tx_context::sender(ctx) == factory.admin,
            error_invalid_caller()
        );
        factory.admin = new_admin;
    }

    // ============ View Functions ============

    public fun get_rescue_delay(factory: &Factory): u64 {
        factory.rescue_delay
    }

    public fun get_access_token_supply(factory: &Factory): u64 {
        factory.access_token_supply
    }

    public fun get_admin(factory: &Factory): address {
        factory.admin
    }

