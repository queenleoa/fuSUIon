// tests/test-wallet-creation.ts
import dotenv from 'dotenv';
dotenv.config();

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { SuiIntegration } from './sui-integration';
import { randomBytes } from 'crypto';

async function testWalletCreation() {
    console.log('🚀 Testing Wallet Creation\n');
    
    // Derive keypair from test private key
    const privateKeyBytes = Buffer.from(process.env.RESOLVER_PRIVATE_KEY!.slice(2), 'hex');
    const keypair = Ed25519Keypair.fromSecretKey(privateKeyBytes.slice(0, 32));
    
    // Create integration instance
    const suiIntegration = new SuiIntegration(
        process.env.SUI_RPC || 'https://fullnode.testnet.sui.io',
        process.env.SUI_ESCROW_PACKAGE_ID || '0x1234',
        keypair
    );
    
    // Test connection first
    await suiIntegration.testConnection();
    
    // Only proceed if we have a package ID
    if (!process.env.SUI_ESCROW_PACKAGE_ID || process.env.SUI_ESCROW_PACKAGE_ID === '0x1234') {
        console.log('\n⚠️  Please deploy your Sui package first and set SUI_ESCROW_PACKAGE_ID in .env');
        return;
    }
    
    // Create a test order hash
    const orderHash = '0x' + randomBytes(32).toString('hex');
    console.log('\nCreating wallet with order hash:', orderHash);
    
    try {
        // Create wallet with 1 SUI
        const walletId = await suiIntegration.createWallet(
            orderHash,
            BigInt(1_000_000), // 1 SUI in MIST
            '0x2::sui::SUI'
        );
        
        console.log('✅ Wallet created successfully:', walletId);
    } catch (error) {
        console.error('❌ Failed to create wallet:', error);
    }
}

testWalletCreation().catch(console.error);