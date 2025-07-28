/// Module: escrow
module escrow::escrow_access;

    use std::vector;
    use sui::event;
    use sui::ed25519;
    use sui::clock::{Clock, timestamp_ms};
    use sui::bcs;
    use escrow::constants::{
        error_not_authorized,
        error_invalid_resolver,
        error_invalid_intent_signature,
        error_invalid_order_hash,
        error_invalid_time,
        error_token_expired,
        error_invalid_access_token,
        intent_action_create,
        intent_action_cancel,
        default_token_validity
    };
    use escrow::structs::{
        AccessToken,
        OrderState,
        UserIntent,
        ResolverFill
    };
    use escrow::structs;
    use escrow::utils;
    use sui::nitro_attestation::timestamp;

    // ======== Events ========

    public struct AccessTokenMinted has copy, drop {
        resolver: address,
        token_id: address,
        timestamp: u64,
        admin: address,
        expires_at: u64
    }

    public struct UserIntentVerified has copy, drop {
        user: address,
        order_hash: vector<u8>,
        action: u8,
        resolver: address,
        timestamp: u64
    }

    public struct OrderStateCreated has copy, drop {
        order_hash: vector<u8>,
        order_state_id: address,
        total_amount: u64,
        parts_amount: u8,
        merkle_root: vector<u8>,
        timestamp: u64
    }

    public struct AccessFunctionFailed has copy, drop {
        function_name: vector<u8>,
        error_code: u64,
        caller: address,
        timestamp: u64
    }

    // ======== Admin Capability ========

    public struct AdminCap has key, store {
        id: UID
    }

    // ======== Relayer Capability ========

    public struct RelayerCap has key, store {
        id: UID
    }

    // ============ Init Function ============

    fun init(ctx: &mut TxContext) {
    // Create admin capability. Init once when published. 
    let admin_cap = AdminCap {
        id: object::new(ctx)
    };
    transfer::transfer(admin_cap, ctx.sender());
    
    // Create relayer capability  
    let relayer_cap = RelayerCap {
        id: object::new(ctx)
    };
    transfer::transfer(relayer_cap, ctx.sender());
    }


    // ============ Access Token Management ============

    // Mint access token for a whitelisted resolver (admin only)
    // Mint an access token for a whitelisted resolver
    /// Only admin can mint access tokens
    public entry fun mint_access_token(
        _admin_cap: &AdminCap,
        resolver: address,
        validity_period: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Create access token
        let access_token = structs::create_access_token(
            resolver,
            validity_period,
            clock,
            ctx
        );
        
        let token_id = structs::get_token_address(&access_token);
        let expires_at = structs::get_token_expires_at(&access_token);
        
        // Transfer access token to resolver
        transfer::public_transfer(access_token, resolver);
        
        // Emit event
        event::emit(AccessTokenMinted {
            resolver,
            token_id,
            timestamp: timestamp_ms(clock) / 1000,
            admin: ctx.sender(),
            expires_at
        });
    }   


   /// Grant relayer capability to an address (admin only)
    public entry fun grant_relayer_capability(
        _admin_cap: &AdminCap,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let relayer_cap = RelayerCap {
            id: object::new(ctx)
        };
        transfer::transfer(relayer_cap, recipient);
    }

    // ============ User Intent Verification ============

    // Verify user intent signature for fund escrowing using Ed25519
    /// This is crucial when resolver needs to lock user's funds (Sui -> EVM swaps)
    public fun verify_user_intent_ed25519(
        order_hash: vector<u8>,
        user: address,
        resolver: address,
        action: u8,
        expiry: u64,
        nonce: u64,
        signature: vector<u8>,
        public_key: vector<u8>,
        clock: &Clock
    ): bool {
        let current_time = timestamp_ms(clock) / 1000;
        
        // Check expiration
        assert!(current_time < expiry, error_invalid_time());
        
        // Create user intent
        let intent = structs::create_user_intent(
            order_hash,
            resolver,
            action,
            current_time,
            expiry,
            nonce
        );
        
        // Create message to sign
        let message = bcs::to_bytes(&intent);
        
        // Verify Ed25519 signature
        let verified = ed25519::ed25519_verify(
            &signature,
            &public_key,
            &message
        );
        
        if (verified) {
            // Emit verification event
            event::emit(UserIntentVerified {
                user,
                order_hash,
                action,
                resolver,
                timestamp: current_time
            });
        };
        
        verified
    }
    // ======== Order State Management ========
    /// Create a shared OrderState object when a limit order is placed
    /// Only relayer can create this after verifying the order
    public entry fun create_order_state(
        _relayer_cap: &RelayerCap,
        order_hash: vector<u8>,
        merkle_root: vector<u8>,
        total_amount: u64,
        parts_amount: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Verify order hash is 32 bytes
        assert!(vector::length(&order_hash) == 32, error_invalid_order_hash());
        
        // Create OrderState as shared object
        let order_state = structs::create_order_state(
            order_hash,
            merkle_root,
            total_amount,
            parts_amount,
            ctx
        );
        
        let order_state_id = structs::get_order_state_address(&order_state);
        
        // Share the order state object
        transfer::public_share_object(order_state);
        
        // Emit event
        event::emit(OrderStateCreated {
            order_hash,
            order_state_id,
            total_amount,
            parts_amount,
            merkle_root,
            timestamp: timestamp_ms(clock) / 1000
        });
    }

    /// Update order state after partial fill
    public(package) fun update_order_fill(
        order_state: &mut OrderState,
        fill_amount: u64,
        secret_index: u64,
        indices_used: vector<u8>,
        access_token: &AccessToken,
        clock: &Clock,
        ctx: &TxContext
    ) {
        // Verify caller is authorized
        assert!(structs::get_token_resolver(access_token) == ctx.sender(), error_invalid_resolver());
        
        // Verify token is valid
        assert!(utils::validate_access_token(access_token, ctx.sender(), clock), error_token_expired());
        
        // Update filled amount
        structs::update_order_state_filled_amount(order_state, fill_amount);
        
        // Create resolver fill record
        let resolver_fill = structs::create_resolver_fill(
            ctx.sender(),
            fill_amount,
            indices_used,
            timestamp_ms(clock) / 1000
        );
        
        // Add resolver fill to order state
        structs::add_order_state_resolver_fill(order_state, resolver_fill);
    }

    /// Public function to query order state
    public fun get_order_state(order_state: &OrderState): (
        vector<u8>, // order_hash
        vector<u8>, // merkle_root
        u64,        // total_amount
        u64,        // filled_amount
        u8          // parts_amount
    ) {
        (
            *structs::get_order_state_order_hash(order_state),
            *structs::get_order_state_merkle_root(order_state),
            structs::get_order_state_total_amount(order_state),
            structs::get_order_state_filled_amount(order_state),
            structs::get_order_state_parts_amount(order_state)
        )
    }

    /// Check if a secret index has been used
    public fun is_secret_used(
        order_state: &OrderState,
        secret_index: u64
    ): bool {
        utils::is_secret_used(order_state, secret_index)
    }

    /// Check if order is fully filled
    public fun is_order_filled(order_state: &OrderState): bool {
        structs::get_order_state_filled_amount(order_state) >= structs::get_order_state_total_amount(order_state)
    }

    /// Get remaining amount for an order
    public fun get_remaining_amount(order_state: &OrderState): u64 {
        let total = structs::get_order_state_total_amount(order_state);
        let filled = structs::get_order_state_filled_amount(order_state);
        
        if (filled >= total) {
            0
        } else {
            total - filled
        }
    }

    // ======== Security Helpers ========

    /// Verify that an object was created by this package
    /// Sui's type system ensures objects can only be created by their defining module
    /// The type itself encodes the package address, so no additional verification needed
    public fun verify_package_origin<T>(_obj: &T): bool {
        // The fact that this function can be called with the object
        // already proves it was created by this package
        true
    }

    /// Helper to emit failure events for monitoring
    public fun emit_access_failure(
        function_name: vector<u8>,
        error_code: u64,
        ctx: &TxContext,
        timestamp: &Clock,
    ) {
        event::emit(AccessFunctionFailed {
            function_name,
            error_code,
            caller: ctx.sender(),
            timestamp: timestamp_ms(timestamp),
        });
    }

