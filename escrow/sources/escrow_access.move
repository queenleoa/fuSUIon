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

    /// Mint access token for a whitelisted resolver (admin only)
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

    /// Verify user intent using secp256k1 (EVM compatible)
    public fun verify_user_intent_secp256k1(
        order_hash: vector<u8>,
        user: address,
        resolver: address,
        action: u8,
        expiry: u64,
        nonce: u64,
        signature: vector<u8>,
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
        
        // Create message and hash it
        let message = bcs::to_bytes(&intent);
        let msg_hash = keccak256(&message);
        
        // Verify signature (assuming signature contains r, s, v)
        assert!(vector::length(&signature) == 65, error_invalid_intent_signature());
        
        // Extract v from last byte
        let v = *vector::borrow(&signature, 64);
        let recovery_id = if (v >= 27) { v - 27 } else { v };
        
        // Recover public key
        let recovered_pubkey = ecdsa_k1::secp256k1_ecrecover(
            &signature,
            &msg_hash,
            recovery_id
        );
        
        // Derive address from recovered public key
        let derived_address = ecdsa_k1::secp256k1_pubkey_to_address(&recovered_pubkey);
        
        let verified = derived_address == user;
        
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
    }nonce: u64,
        signature: vector<u8>
    ): SignedUserIntent {
        SignedUserIntent {
            user,
            order_hash,
            amount,
            src_token,
            dst_token,
            chain_id,
            expiration,
            nonce,
            signature
        }
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
