/// Module: escrow
module escrow::escrow_access;

    use std::vector;
    use sui::event;
    use sui::hash::keccak256;
    use sui::ed25519;
    use sui::ecdsa_k1;
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
        // Create admin capability
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

    /// Mint access token for a whitelisted resolver (admin only)
    public fun mint_access_token(
        _: &AdminCap,
        resolver: address,
        validity_period: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): AccessToken {
        let token = create_access_token(
            resolver,
            validity_period,
            clock,
            ctx
        );

        // Emit event
        event::emit(AccessTokenMinted {
            token_id: structs::get_token_address(&token),
            resolver: structs::get_token_resolver(&token),
            minted_at: structs::get_token_minted_at(&token),
            expires_at: structs::get_token_expires_at(&token),
        });

        token
    }

    /// Mint access token with default validity period
    public fun mint_access_token_default(
        admin_cap: &AdminCap,
        resolver: address,
        clock: &Clock,
        ctx: &mut TxContext
    ): AccessToken {
        mint_access_token(admin_cap, resolver, default_token_validity(), clock, ctx)
    }

    /// Grant relayer capability to an address (admin only)
    public fun grant_relayer_capability(
        _: &AdminCap,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let relayer_cap = RelayerCap {
            id: object::new(ctx)
        };
        transfer::transfer(relayer_cap, recipient);
    }

    /// Check if access token is valid
    public fun validate_access_token(
        token: &AccessToken,
        resolver: address,
        clock: &Clock
    ): bool {
        utils::validate_access_token(token, resolver, clock)
    }

    // ============ User Intent Verification ============

    /// Verify user intent with Ed25519 signature (Sui native)
    public fun verify_user_intent_ed25519(
        order_hash: vector<u8>,
        maker: address,
        resolver: address,
        action: u8,
        expiry: u64,
        nonce: u64,
        signature: vector<u8>,
        public_key: vector<u8>,
        clock: &Clock
    ): bool {
        // Check expiry
        let current_time = timestamp_ms(clock) / 1000;
        if (current_time >= expiry) {
            return false
        };

        // Create intent message
        let intent = structs::create_user_intent {
            order_hash,
            resolver,
            action,
            expiry,
            nonce,
        };

        // Serialize intent with Sui prefix
        let message = constants::create_sui_intent_message(bcs::to_bytes(&intent));

        // Verify signature
        let verified = ed25519::ed25519_verify(
            &signature,
            &public_key,
            &message
        );

        if (verified) {
            // Emit verification event
            event::emit(UserIntentVerified {
                order_hash,
                maker,
                resolver,
                action,
                verified_at: current_time,
            });
        };

        verified
    }

    /// Verify user intent with secp256k1 signature (EVM compatible)
    public fun verify_user_intent_secp256k1(
        order_hash: vector<u8>,
        maker: address,
        resolver: address,
        action: u8,
        expiry: u64,
        nonce: u64,
        signature: vector<u8>,
        clock: &Clock
    ): bool {
        // Check expiry
        let current_time = timestamp_ms(clock) / 1000;
        if (current_time >= expiry) {
            return false
        };

        // Create intent message
        let intent = structs::create_user_intent {
            order_hash,
            resolver,
            action,
            expiry,
            nonce,
        };

        // Serialize intent
        let message = bcs::to_bytes(&intent);
        let msg_hash = sui::hash::keccak256(&message);

        // Recover signer address from signature
        let recovered_pubkey = ecdsa_k1::secp256k1_ecrecover(
            &signature,
            &msg_hash,
            0 // recovery_id (v - 27)
        );

        // Derive address from public key
        let recovered_address = ecdsa_k1::secp256k1_pubkey_to_address(&recovered_pubkey);

        let verified = recovered_address == maker;

        if (verified) {
            // Emit verification event
            event::emit(UserIntentVerified {
                order_hash,
                maker,
                resolver,
                action,
                verified_at: current_time,
            });
        };

        verified
    }

    // ============ OrderState Management ============

    /// Create a new OrderState (relayer only)
    public fun create_order_state_object(
        _: &RelayerCap,
        order_hash: vector<u8>,
        merkle_root: vector<u8>,
        total_amount: u64,
        parts_amount: u8,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Validate parameters
        assert!(
            vector::length(&order_hash) == 32,
            error_invalid_order_hash()
        );

        let order_state = create_order_state(
            order_hash,
            merkle_root,
            total_amount,
            parts_amount,
            ctx
        );

        let order_state_id = object::uid_to_address(&order_state.id);

        // Emit event
        event::emit(OrderStateCreated {
            order_state_id,
            order_hash,
            merkle_root,
            total_amount,
            parts_amount,
            created_at: timestamp_ms(clock) / 1000,
        });

        // Share the object for public access
        transfer::share_object(order_state);
    }

    // ============ Public Query Functions ============

    /// Get order state details
    public fun get_order_details(order_state: &OrderState): (
        vector<u8>, // order_hash
        vector<u8>, // merkle_root
        u64,        // total_amount
        u64,        // filled_amount
        u8,         // parts_amount
        vector<u8>  // used_indices
    ) {
        (
            *get_order_state_order_hash(order_state),
            *get_order_state_merkle_root(order_state),
            get_order_state_total_amount(order_state),
            get_order_state_filled_amount(order_state),
            get_order_state_parts_amount(order_state),
            *get_order_state_used_indices(order_state)
        )
    }

    /// Check if an order is fully filled
    public fun is_order_filled(order_state: &OrderState): bool {
        get_order_state_filled_amount(order_state) >= get_order_state_total_amount(order_state)
    }

    /// Get remaining amount for an order
    public fun get_remaining_amount(order_state: &OrderState): u64 {
        let total = get_order_state_total_amount(order_state);
        let filled = get_order_state_filled_amount(order_state);
        
        if (filled >= total) {
            0
        } else {
            total - filled
        }
    }

    /// Check if a secret index has been used
    public fun is_index_used(order_state: &OrderState, index: u64): bool {
        utils::is_secret_used(order_state, index)
    }

    /// Get fill percentage (in basis points, 10000 = 100%)
    public fun get_fill_percentage(order_state: &OrderState): u64 {
        let total = get_order_state_total_amount(order_state);
        if (total == 0) {
            return 10000 // 100% if total is 0
        };
        
        let filled = get_order_state_filled_amount(order_state);
        (filled * 10000) / total
    }

    // ============ Helper Functions ============

    /// Create intent message for signing
    public fun create_intent_message(
        order_hash: vector<u8>,
        resolver: address,
        action: u8,
        expiry: u64,
        nonce: u64
    ): vector<u8> {
        let intent = structs::create_user_intent {
            order_hash,
            resolver,
            action,
            expiry,
            nonce,
        };
        
        utils::create_sui_intent_message(bcs::to_bytes(&intent))
    }


    // ============ Tests ============

  /*  #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::test_utils;

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

    #[test]
    fun test_access_token_minting() {
        let mut scenario = test_scenario::begin(@0x1);
        
        // Init module
        test_scenario::next_tx(&mut scenario, @0x1);
        {
            test_init(test_scenario::ctx(&mut scenario));
        };
        
        // Mint access token
        test_scenario::next_tx(&mut scenario, @0x1);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&scenario);
            let clock = test_utils::create_clock(test_scenario::ctx(&mut scenario));
            
            let token = mint_access_token(
                &admin_cap,
                @0x2,
                3600,
                &clock,
                test_scenario::ctx(&mut scenario)
            );
            
            assert!(get_token_resolver(&token) == @0x2, 0);
            
            transfer::transfer(token, @0x2);
            test_scenario::return_to_sender(&scenario, admin_cap);
            test_utils::destroy(clock);
        };
        
        test_scenario::end(scenario);
    }
    */
