// tests/test-sui-integration.ts
import dotenv from 'dotenv';
dotenv.config();

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { SuiIntegration } from './sui-integration';

async function testSuiIntegration() {
    console.log('🚀 Testing Sui Integration\n');
    
    // Create a test keypair
    // In production, you'd derive this from your private key
    const keypair = new Ed25519Keypair();
    
    // Create integration instance
    const suiIntegration = new SuiIntegration(
        process.env.SUI_RPC || 'https://fullnode.testnet.sui.io',
        process.env.SUI_ESCROW_PACKAGE_ID || '0x1234', // You'll replace this
        keypair
    );
    
    // Test connection
    await suiIntegration.testConnection();
}

// Run the test
testSuiIntegration().catch(console.error);