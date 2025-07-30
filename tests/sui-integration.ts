// tests/sui-integration.ts

// Import Sui SDK with the NEWEST syntax
import { 
    getFullnodeUrl, 
    SuiClient, 
    SuiTransactionBlockResponse,
    SuiObjectResponse
} from '@mysten/sui/client';

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Secp256k1Keypair } from '@mysten/sui/keypairs/secp256k1';
import { Transaction } from '@mysten/sui/transactions';  // <-- Changed from TransactionBlock
import { bcs } from '@mysten/sui/bcs';

// Import utilities we'll need
import Sdk from '@1inch/cross-chain-sdk';
import { keccak256, randomBytes, parseUnits } from 'ethers';

// Let's define the structure of your Sui escrow data
export interface SuiEscrowImmutables {
    orderHash: string
    hashlock: string
    maker: string
    taker: string
    tokenType: string
    amount: bigint
    safetyDeposit: bigint
    resolver: string
    timelocks: {
        deployedAt: bigint
        srcWithdrawal: bigint
        srcPublicWithdrawal: bigint
        srcCancellation: bigint
        srcPublicCancellation: bigint
        dstWithdrawal: bigint
        dstPublicWithdrawal: bigint
        dstCancellation: bigint
    }
}

// Main class that will handle all Sui interactions
export class SuiIntegration {
    private client: SuiClient;
    private keypair: Ed25519Keypair | Secp256k1Keypair;
    
    constructor(
        private rpcUrl: string,
        private escrowPackageId: string,
        keypair: Ed25519Keypair | Secp256k1Keypair
    ) {
        // Use the new SuiClient syntax
        this.client = new SuiClient({ url: rpcUrl });
        this.keypair = keypair;
    }
    
    /**
     * Test connection and get package info
     */
    async testConnection(): Promise<void> {
        try {
            // Test 1: Check client connection
            const checkpoint = await this.client.getLatestCheckpointSequenceNumber();
            console.log(`✅ Connected to Sui at ${this.rpcUrl}`);
            console.log(`   Latest checkpoint: ${checkpoint}`);
            
            // Test 2: Get our address
            const address = this.keypair.getPublicKey().toSuiAddress();
            console.log(`✅ Using address: ${address}`);
            
            // Test 3: Check if package exists
            const packageObj = await this.client.getObject({
                id: this.escrowPackageId,
                options: { showContent: true }
            });
            
            if (packageObj.data) {
                console.log(`✅ Found escrow package at: ${this.escrowPackageId}`);
            } else {
                console.log(`❌ Package not found at: ${this.escrowPackageId}`);
            }
            
            // Test 4: Get balance
            const balance = await this.client.getBalance({
                owner: address
            });
            console.log(`✅ Balance: ${balance.totalBalance} MIST (${Number(balance.totalBalance) / 1e9} SUI)`);
            
        } catch (error) {
            console.error('❌ Connection test failed:', error);
            throw error;
        }
    }
}