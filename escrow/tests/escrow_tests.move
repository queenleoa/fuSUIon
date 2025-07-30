#[test_only]
module escrow::escrow_tests; 

    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::hash;
 
    use escrow::escrow_create::{Self};
    use escrow::escrow_withdraw::{Self};
    use escrow::escrow_cancel::{Self};
    use escrow::structs::{Self, Wallet, EscrowSrc, EscrowDst};
    use escrow::utils;
    use escrow::constants;
    
    // Test constants
    const MAKER: address = @0xA;
    const TAKER: address = @0xB; 
    const RESOLVER: address = @0xC;
    const OTHER_RESOLVER: address = @0xD;
    
    const AMOUNT: u64 = 1_000_000_000; // 1 SUI
    const SAFETY_DEPOSIT: u64 = 100_000_000; // 0.1 SUI
    
    // Test secret and hashlock
    const SECRET: vector<u8> = b"test_secret_32_bytes_long_1234567";
    
    fun setup_test(): (Scenario, Clock, vector<u8>, vector<u8>) {
        let mut scenario = test::begin(MAKER);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        let secret = SECRET;
        let order_hash = b"order_hash_32_bytes_long_1234567";
        let hashlock = hash::keccak256(&secret);
        
        (scenario, clock, order_hash, hashlock)
    }
    
    fun mint_sui(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ctx(scenario))
    }
    
    #[test]
    fun test_create_wallet() {
        let (mut scenario, clock, order_hash, _) = setup_test();
        
        next_tx(&mut scenario, MAKER);
        {
            let funding = mint_sui(AMOUNT, &mut scenario);
            escrow_create::create_wallet(
                order_hash,
                funding,
                &clock,
                ctx(&mut scenario)
            );
        };
        
        // Verify wallet exists
        next_tx(&mut scenario, MAKER);
        {
            let wallet = test::take_shared<Wallet>(&scenario);
            assert!(structs::wallet_order_hash(&wallet) == &order_hash, 0);
            assert!(structs::wallet_maker(&wallet) == MAKER, 1);
            assert!(structs::wallet_initial_amount(&wallet) == AMOUNT, 2);
            assert!(structs::wallet_is_active(&wallet), 3);
            test::return_shared(wallet);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    #[test]
    fun test_create_src_escrow() {
        let (mut scenario, clock, order_hash, hashlock) = setup_test();
        
        // Create wallet first
        next_tx(&mut scenario, MAKER);
        {
            let funding = mint_sui(AMOUNT * 2, &mut scenario);
            escrow_create::create_wallet(
                order_hash,
                funding,
                &clock,
                ctx(&mut scenario)
            );
        };
        
        // Create source escrow
        next_tx(&mut scenario, RESOLVER);
        {
            let mut wallet = test::take_shared<Wallet>(&scenario);
            let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
            let current_time = clock::timestamp_ms(&clock);
            escrow_create::create_escrow_src(
                &mut wallet,
                hashlock,
                TAKER,
                AMOUNT,
                safety_deposit,
                // Timelock parameters
                current_time + 300_000,  // src_withdrawal (+5 min)
                current_time + 600_000,  // src_public_withdrawal (+10 min)
                current_time + 900_000,  // src_cancellation (+15 min)
                current_time + 1200_000, // src_public_cancellation (+20 min)
                current_time + 250_000,  // dst_withdrawal
                current_time + 550_000,  // dst_public_withdrawal
                current_time + 850_000,  // dst_cancellation
                &clock,
                ctx(&mut scenario)
            );
            
            test::return_shared(wallet);
        };
        
        // Verify escrow exists
        next_tx(&mut scenario, RESOLVER);
        {
            let escrow = test::take_shared<EscrowSrc<SUI>>(&scenario);
            let immutables = structs::get_src_immutables(&escrow);
            
            assert!(structs::get_hashlock(immutables) == &hashlock, 0);
            assert!(structs::get_taker(immutables) == TAKER, 1);
            assert!(structs::get_resolver(immutables) == RESOLVER, 2);
            assert!(structs::get_amount(immutables) == AMOUNT, 3);
            assert!(structs::get_src_status(&escrow) == constants::status_active(), 4);
            
            test::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    #[test]
    fun test_create_dst_escrow() {
        let (mut scenario, clock, order_hash, hashlock) = setup_test();
        
        // Create destination escrow (taker deposits for maker)
        next_tx(&mut scenario, TAKER);
        {
            let token_deposit = mint_sui(AMOUNT, &mut scenario);
            let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
            let current_time = clock::timestamp_ms(&clock);
            escrow_create::create_escrow_dst(
                order_hash,
                hashlock,
                MAKER, // maker receives on dst
                token_deposit,
                safety_deposit,
                // Timelock parameters
                current_time + 300_000,  // src_withdrawal
                current_time + 600_000,  // src_public_withdrawal
                current_time + 900_000,  // src_cancellation
                current_time + 1200_000, // src_public_cancellation
                current_time + 250_000,  // dst_withdrawal
                current_time + 550_000,  // dst_public_withdrawal
                current_time + 850_000,  // dst_cancellation
                &clock,
                ctx(&mut scenario)
            );
        };
        
        // Verify escrow exists
        next_tx(&mut scenario, TAKER);
        {
            let escrow = test::take_shared<EscrowDst<SUI>>(&scenario);
            let immutables = structs::get_dst_immutables(&escrow);
            
            assert!(structs::get_order_hash(immutables) == &order_hash, 0);
            assert!(structs::get_maker(immutables) == MAKER, 1);
            assert!(structs::get_taker(immutables) == TAKER, 2);
            assert!(structs::get_amount(immutables) == AMOUNT, 3);
            assert!(structs::get_dst_status(&escrow) == constants::status_active(), 4);
            
            test::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    #[test]
    fun test_withdraw_src_with_secret() {
        let (mut scenario, mut clock, order_hash, hashlock) = setup_test();
        
        // Setup: Create wallet and escrow
        next_tx(&mut scenario, MAKER);
        {
            let funding = mint_sui(AMOUNT * 2, &mut scenario);
            escrow_create::create_wallet(
                order_hash,
                funding,
                &clock,
                ctx(&mut scenario)
            );
        };
        
        next_tx(&mut scenario, RESOLVER);
        {
            let mut wallet = test::take_shared<Wallet>(&scenario);
            let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
            let current_time = clock::timestamp_ms(&clock);
            escrow_create::create_escrow_src(
                &mut wallet,
                hashlock,
                TAKER,
                AMOUNT,
                safety_deposit,
                current_time + 1000,    // Very short timelocks for testing
                current_time + 2000,
                current_time + 3000,
                current_time + 4000,
                current_time + 900,
                current_time + 1900,
                current_time + 2900,
                &clock,
                ctx(&mut scenario)
            );
            
            test::return_shared(wallet);
        };
        
        // Advance time past finality lock
        clock::increment_for_testing(&mut clock, 1500);
        
        // Withdraw with secret
        next_tx(&mut scenario, RESOLVER);
        {
            let mut escrow = test::take_shared<EscrowSrc<SUI>>(&scenario);
            
            escrow_withdraw::withdraw_src(
                &mut escrow,
                SECRET,
                &clock,
                ctx(&mut scenario)
            );
            
            // Verify status changed
            assert!(structs::get_src_status(&escrow) == constants::status_withdrawn(), 0);
            
            test::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    #[test]
    fun test_withdraw_dst_with_secret() {
        let (mut scenario, mut clock, order_hash, hashlock) = setup_test();
        
        // Create destination escrow
        next_tx(&mut scenario, TAKER);
        {
            let token_deposit = mint_sui(AMOUNT, &mut scenario);
            let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
            let current_time = clock::timestamp_ms(&clock);
            escrow_create::create_escrow_dst(
                order_hash,
                hashlock,
                MAKER,
                token_deposit,
                safety_deposit,
                current_time + 1000,
                current_time + 2000,
                current_time + 3000,
                current_time + 4000,
                current_time + 900,
                current_time + 1900,
                current_time + 2900,
                &clock,
                ctx(&mut scenario)
            );
        };
        
        // Advance time past finality lock
        clock::increment_for_testing(&mut clock, 1500);
        
        // Withdraw with secret (resolver withdraws, funds go to maker)
        next_tx(&mut scenario, TAKER); // Taker is resolver for dst
        {
            let mut escrow = test::take_shared<EscrowDst<SUI>>(&scenario);
            
            escrow_withdraw::withdraw_dst(
                &mut escrow,
                SECRET,
                &clock,
                ctx(&mut scenario)
            );
            
            assert!(structs::get_dst_status(&escrow) == constants::status_withdrawn(), 0);
            
            test::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    #[test]
    fun test_public_withdraw_after_timeout() {
        let (mut scenario, mut clock, order_hash, hashlock) = setup_test();
        
        // Setup escrow
        next_tx(&mut scenario, TAKER);
        {
            let token_deposit = mint_sui(AMOUNT, &mut scenario);
            let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
            let current_time = clock::timestamp_ms(&clock);
            escrow_create::create_escrow_dst(
                order_hash,
                hashlock,
                MAKER,
                token_deposit,
                safety_deposit,
                current_time + 1000,  // src timelocks
                current_time + 2000,
                current_time + 3000,
                current_time + 4000,
                current_time + 900,  // dst_withdrawal (finality)
                current_time + 1900,  // dst_public_withdrawal
                current_time + 2900,  // dst_cancellation
                &clock,
                ctx(&mut scenario)
            );
        };
        
        // Advance time to public withdrawal period
        clock::increment_for_testing(&mut clock, 2500);
        
        // Any resolver can withdraw now
        next_tx(&mut scenario, OTHER_RESOLVER);
        {
            let mut escrow = test::take_shared<EscrowDst<SUI>>(&scenario);
            
            escrow_withdraw::withdraw_dst(
                &mut escrow,
                SECRET,
                &clock,
                ctx(&mut scenario)
            );
            
            test::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    #[test]
    fun test_cancel_src_escrow() {
        let (mut scenario, mut clock, order_hash, hashlock) = setup_test();
        
        // Setup wallet and escrow
        next_tx(&mut scenario, MAKER);
        {
            let funding = mint_sui(AMOUNT * 2, &mut scenario);
            escrow_create::create_wallet(
                order_hash,
                funding,
                &clock,
                ctx(&mut scenario)
            );
        };
        
        next_tx(&mut scenario, RESOLVER);
        {
            let mut wallet = test::take_shared<Wallet>(&scenario);
            let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
            let current_time = clock::timestamp_ms(&clock);
            escrow_create::create_escrow_src(
                &mut wallet,
                hashlock,
                TAKER,
                AMOUNT,
                safety_deposit,
                current_time + 1000,
                current_time + 2000,
                current_time + 3000,  // src_cancellation
                current_time + 4000,
                current_time + 900,
                current_time + 1900,
                current_time + 2900,
                &clock,
                ctx(&mut scenario)
            );
            
            test::return_shared(wallet);
        };
        
        // Advance time to cancellation period
        clock::increment_for_testing(&mut clock, 3500);
        
        // Cancel escrow (returns funds to maker wallet)
        next_tx(&mut scenario, RESOLVER);
        {
            let mut escrow = test::take_shared<EscrowSrc<SUI>>(&scenario);
            let wallet = test::take_shared<Wallet>(&scenario);
            
            escrow_cancel::cancel_src(
                &mut escrow,
                &clock,
                ctx(&mut scenario)
            );
            
            assert!(structs::get_src_status(&escrow) == constants::status_cancelled(), 0);
            
            test::return_shared(escrow);
            test::return_shared(wallet);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    #[test]
    fun test_cancel_dst_escrow() {
        let (mut scenario, mut clock, order_hash, hashlock) = setup_test();
        
        // Create destination escrow
        next_tx(&mut scenario, TAKER);
        {
            let token_deposit = mint_sui(AMOUNT, &mut scenario);
            let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
            let current_time = clock::timestamp_ms(&clock);
            escrow_create::create_escrow_dst(
                order_hash,
                hashlock,
                MAKER,
                token_deposit,
                safety_deposit,
                current_time + 1000,
                current_time + 2000,
                current_time + 3000,
                current_time + 4000,
                current_time + 900,
                current_time + 1900,
                current_time + 2900,  // dst_cancellation
                &clock,
                ctx(&mut scenario)
            );
        };
        
        // Advance time to cancellation period
        clock::increment_for_testing(&mut clock, 3500);
        
        // Cancel escrow (returns funds to taker)
        next_tx(&mut scenario, TAKER);
        {
            let mut escrow = test::take_shared<EscrowDst<SUI>>(&scenario);
            
            escrow_cancel::cancel_dst(
                &mut escrow,
                &clock,
                ctx(&mut scenario)
            );
            
            assert!(structs::get_dst_status(&escrow) == constants::status_cancelled(), 0);
            
            test::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
    
    // #[test]
    // #[expected_failure(abort_code = constants::e_invalid_secret,)]
    // fun test_withdraw_with_invalid_secret() {
    //     let (mut scenario, mut clock, order_hash, hashlock) = setup_test();
        
    //     // Setup escrow
    //     next_tx(&mut scenario, TAKER);
    //     {
    //         let token_deposit = mint_sui(AMOUNT, &mut scenario);
    //         let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
    //         let current_time = clock::timestamp_ms(&clock);
    //         escrow_create::create_escrow_dst(
    //             order_hash,
    //             hashlock,
    //             MAKER,
    //             token_deposit,
    //             safety_deposit,
    //             current_time + 1000,
    //             current_time + 2000,
    //             current_time + 3000,
    //             current_time + 4000,
    //             current_time + 1000,
    //             current_time + 2000,
    //             current_time + 3000,
    //             &clock,
    //             ctx(&mut scenario)
    //         );
    //     };
        
    //     // Advance time past finality lock
    //     clock::increment_for_testing(&mut clock, 1500);
        
    //     // Try to withdraw with wrong secret
    //     next_tx(&mut scenario, TAKER);
    //     {
    //         let mut escrow = test::take_shared<EscrowDst<SUI>>(&scenario);
    //         let wrong_secret = b"wrong_secret_that_doesnt_match_!";
            
    //         escrow_withdraw::withdraw_dst(
    //             &mut escrow,
    //             wrong_secret,
    //             &clock,
    //             ctx(&mut scenario)
    //         );
            
    //         test::return_shared(escrow);
    //     };
        
    //     clock::destroy_for_testing(clock);
    //     test::end(scenario);
    // }
    
    // #[test]
    // #[expected_failure(abort_code = constants::e_not_withdrawable,)]
    // fun test_withdraw_before_finality_lock() {
    //     let (mut scenario, clock, order_hash, hashlock) = setup_test();
        
    //     // Setup escrow
    //     next_tx(&mut scenario, TAKER);
    //     {
    //         let token_deposit = mint_sui(AMOUNT, &mut scenario);
    //         let safety_deposit = mint_sui(SAFETY_DEPOSIT, &mut scenario);
            
    //         let current_time = clock::timestamp_ms(&clock);
    //         escrow_create::create_escrow_dst(
    //             order_hash,
    //             hashlock,
    //             MAKER,
    //             token_deposit,
    //             safety_deposit,
    //             current_time + 10000,  // All timelocks far in future
    //             current_time + 20000,
    //             current_time + 30000,
    //             current_time + 40000,
    //             current_time + 10000,  // Finality lock not reached
    //             current_time + 20000,
    //             current_time + 30000,
    //             &clock,
    //             ctx(&mut scenario)
    //         );
    //     };
        
    //     // Try to withdraw immediately (should fail)
    //     next_tx(&mut scenario, TAKER);
    //     {
    //         let mut escrow = test::take_shared<EscrowDst<SUI>>(&scenario);
            
    //         escrow_withdraw::withdraw_dst(
    //             &mut escrow,
    //             SECRET,
    //             &clock,
    //             ctx(&mut scenario)
    //         );
            
    //         test::return_shared(escrow);
    //     };
        
    //     clock::destroy_for_testing(clock);
    //     test::end(scenario);
    // }
    
    // #[test]
    // fun test_wallet_withdraw() {
    //     let (mut scenario, clock, order_hash, _) = setup_test();
        
    //     // Create wallet
    //     next_tx(&mut scenario, MAKER);
    //     {
    //         let funding = mint_sui(AMOUNT * 2, &mut scenario);
    //         escrow_create::create_wallet(
    //             order_hash,
    //             funding,
    //             &clock,
    //             ctx(&mut scenario)
    //         );
    //     };
        
    //     // Maker withdraws from wallet
    //     next_tx(&mut scenario, MAKER);
    //     {
    //         let mut wallet = test::take_shared<Wallet>(&scenario);
            
    //         escrow_create::withdraw_from_wallet(
    //             &mut wallet,
    //             AMOUNT,
    //             ctx(&mut scenario)
    //         );
            
    //         // Verify remaining balance
    //         assert!(structs::wallet_balance(&wallet) == AMOUNT, 0);
            
    //         test::return_shared(wallet);
    //     };
        
    //     clock::destroy_for_testing(clock);
    //     test::end(scenario);
    // }
    
    #[test]
    fun test_hashlock_validation() {
        let valid_secret = b"test_secret_32_bytes_long_123456";
        let hashlock = hash::keccak256(&valid_secret);
        
        // Test valid secret
        assert!(utils::validate_hashlock(&valid_secret, &hashlock), 0);
        assert!(utils::validate_secret_length(&valid_secret), 1);
        
        // Test invalid secret
        let invalid_secret = b"wrong_secret_32_bytes_long_12345";
        assert!(!utils::validate_hashlock(&invalid_secret, &hashlock), 2);
        
        // Test short secret
        let short_secret = b"too_short";
        assert!(!utils::validate_secret_length(&short_secret), 3);
    }