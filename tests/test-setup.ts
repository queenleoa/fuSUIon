// tests/test-setup.ts
console.log("✅ TypeScript is working!");
console.log("📦 Node version:", process.version);

// Test imports
import { ethers } from 'ethers';
console.log("✅ Ethers imported successfully");

import dotenv from 'dotenv';
dotenv.config();
console.log("✅ Environment loaded");

// Test 1inch SDK
import Sdk from '@1inch/cross-chain-sdk';
console.log("✅ 1inch SDK imported successfully");

// // Test Sui SDK - UPDATED IMPORT!
import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';  
console.log("✅ Sui SDK imported successfully");

// Test we can connect to networks
async function testConnections() {
    // Test Ethereum connection
    const ethProvider = new ethers.JsonRpcProvider(process.env.SRC_CHAIN_RPC);
    const blockNumber = await ethProvider.getBlockNumber();
    console.log("✅ Connected to Ethereum, block:", blockNumber);

    const rpcUrl = process.env.SUI_RPC ?? getFullnodeUrl('devnet'); // 'mainnet' | 'testnet' | 'localnet'

	// 2. Construct the client.  (The old `Connection` class is gone.)
	const client = new SuiClient({ url: rpcUrl });

	// 3. Ping the node – any cheap RPC works. Latest checkpoint is simple.
	const latest = await client.getLatestCheckpointSequenceNumber();

	console.log(`✅  Connected to Sui RPC (${rpcUrl}). Latest checkpoint: ${latest}`);

}

// Run the tests
testConnections().catch(console.error);