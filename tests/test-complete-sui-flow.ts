// tests/test-complete-sui-flow.ts
import dotenv from 'dotenv';
dotenv.config();

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { SuiIntegration } from './sui-integration';
import { randomBytes } from 'crypto';
import { keccak256 } from 'ethers';

async function testCompleteSuiFlow() {
    console.log('🚀 Testing Complete Sui Escrow Flow\n');
    
    // Setup keypairs
    const userKeypair = Ed25519Keypair.fromSecretKey(
        Buffer.from(process.env.USER_PRIVATE_KEY!.slice(2), 'hex').slice(0, 32)
    );
    const resolverKeypair = Ed25519Keypair.fromSecretKey(
        Buffer.from(process.env.RESOLVER_PRIVATE_KEY!.slice(2), 'hex').slice(0, 32)
    );
    
    // Create integrations
    const userIntegration = new SuiIntegration(
        process.env.SUI_RPC || 'https://fullnode.testnet.sui.io',
        process.env.SUI_ESCROW_PACKAGE_ID!,
        userKeypair
    );
    
    const resolverIntegration = new SuiIntegration(
        process.env.SUI_RPC || 'https://fullnode.testnet.sui.io',
        process.env.SUI_ESCROW_PACKAGE_ID!,
        resolverKeypair
    );
    
    // Test data
    const orderHash = '0x' + randomBytes(32).toString('hex');
    const secret = '0x' + randomBytes(32).toString('hex');
    const hashlock = keccak256(secret);
    
    console.log('📋 Test Data:');
    console.log('  Order Hash:', orderHash.slice(0, 10) + '...');
    console.log('  Secret:', secret.slice(0, 10) + '...');
    console.log('  Hashlock:', hashlock.slice(0, 10) + '...');
    
    try {
        // Step 1: User creates wallet
        console.log('\n1️⃣ User creating wallet...');
        const walletId = await userIntegration.createWallet(
            orderHash,
            BigInt(1_000_000), // 1 SUI
            '0x2::sui::SUI'
        );
        
        // Step 2: Resolver creates source escrow
        console.log('\n2️⃣ Resolver creating source escrow...');
        const srcEscrowId = await resolverIntegration.createSrcEscrow(
            walletId,
            hashlock,
            '0x742d35Cc6634C0532925a3b844Bc9e7595f5fF8B', // Example EVM address
            BigInt(900_000), // 0.9 SUI (keeping 0.1 for fees)
            BigInt(100_000_000), // 0.1 SUI safety deposit
            {
                srcWithdrawal: 10,      // 10 seconds for testing
                srcPublicWithdrawal: 20,
                srcCancellation: 30,
                srcPublicCancellation: 40,
                dstWithdrawal: 5,
                dstPublicWithdrawal: 15,
                dstCancellation: 25
            }
        );
        
        // Step 3: Create a destination escrow (simulating the other side)
        console.log('\n3️⃣ Creating destination escrow (simulating cross-chain)...');
        const dstEscrowId = await resolverIntegration.createDstEscrow(
            orderHash,
            hashlock,
            userKeypair.getPublicKey().toSuiAddress(), // User receives on Sui
            BigInt(800_000), // 0.8 SUI
            BigInt(100_000_000), // 0.1 SUI safety deposit
            {
                srcWithdrawal: 10,
                srcPublicWithdrawal: 20,
                srcCancellation: 30,
                srcPublicCancellation: 40,
                dstWithdrawal: 5,
                dstPublicWithdrawal: 15,
                dstCancellation: 25
            }
        );
        
        // Wait for timelock
        console.log('\n⏳ Waiting 10 seconds for timelock to pass...');
        await new Promise(resolve => setTimeout(resolve, 10000));
        
        // Step 4: Withdraw from destination (user gets funds)
        console.log('\n4️⃣ User withdrawing from destination escrow...');
        await resolverIntegration.withdraw(dstEscrowId, 'dst', secret);
        
        // Step 5: Withdraw from source (resolver gets funds)
        console.log('\n5️⃣ Resolver withdrawing from source escrow...');
        await resolverIntegration.withdraw(srcEscrowId, 'src', secret);
        
        console.log('\n✅ Complete flow test successful!');
        console.log('\n📊 Summary:');
        console.log('  Wallet:', walletId);
        console.log('  Source Escrow:', srcEscrowId);
        console.log('  Destination Escrow:', dstEscrowId);
        
    } catch (error) {
        console.error('\n❌ Test failed:', error);
        
        // If it's a Move abort, show the error code
        if (console.error.toString().includes('MoveAbort')) {
            console.error('\n💡 Move Error Code Reference:');
            console.error('  1001: Invalid amount');
            console.error('  1004: Invalid secret');
            console.error('  1006: Already withdrawn');
            console.error('  1007: Not withdrawable (timelock)');
            console.error('  1010: Unauthorized');
        }
    }
}

testCompleteSuiFlow().catch(console.error);