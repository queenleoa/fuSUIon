// tests/setup-test-accounts.ts
import dotenv from 'dotenv';
dotenv.config();

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { SuiClient } from '@mysten/sui/client';

async function setupTestAccounts() {
    console.log('🔧 Setting up test accounts\n');
    
    const client = new SuiClient({ 
        url: process.env.SUI_RPC || 'https://fullnode.testnet.sui.io' 
    });
    
    // Derive keypairs from test private keys
    const userPrivateKey = Buffer.from(process.env.USER_PRIVATE_KEY!.slice(2), 'hex');
    const resolverPrivateKey = Buffer.from(process.env.RESOLVER_PRIVATE_KEY!.slice(2), 'hex');
    
    const userKeypair = Ed25519Keypair.fromSecretKey(userPrivateKey.slice(0, 32));
    const resolverKeypair = Ed25519Keypair.fromSecretKey(resolverPrivateKey.slice(0, 32));
    
    // Get addresses
    const userAddress = userKeypair.getPublicKey().toSuiAddress();
    const resolverAddress = resolverKeypair.getPublicKey().toSuiAddress();
    
    console.log('👤 User Address:', userAddress);
    console.log('🤖 Resolver Address:', resolverAddress);
    
    // Check balances
    const userBalance = await client.getBalance({ owner: userAddress });
    const resolverBalance = await client.getBalance({ owner: resolverAddress });
    
    console.log('\n💰 Balances:');
    console.log(`User: ${Number(userBalance.totalBalance) / 1e9} SUI`);
    console.log(`Resolver: ${Number(resolverBalance.totalBalance) / 1e9} SUI`);
    
    // Fund accounts if needed
    if (Number(userBalance.totalBalance) < 1e9) {
        console.log('\n📥 User needs funding. Run:');
        console.log(`curl -X POST https://faucet.testnet.sui.io/gas -H "Content-Type: application/json" -d '{"FixedAmountRequest":{"recipient":"${userAddress}"}}'`);
    }
    
    if (Number(resolverBalance.totalBalance) < 1e9) {
        console.log('\n📥 Resolver needs funding. Run:');
        console.log(`curl -X POST https://faucet.testnet.sui.io/gas -H "Content-Type: application/json" -d '{"FixedAmountRequest":{"recipient":"${resolverAddress}"}}'`);
    }
    
    return { userAddress, resolverAddress };
}

setupTestAccounts().catch(console.error);