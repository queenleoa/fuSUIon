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

// Sui system objects
const SUI_CLOCK_OBJECT_ID = '0x0000000000000000000000000000000000000000000000000000000000000006';

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

    /**
     * Convert EVM address to Sui address format for cross-chain mapping
     * This is a simplified version - in production you'd want a proper mapping system
     */
    private evmAddressToSuiAddress(evmAddress: string): string {
        // For MVP: use a deterministic mapping based on EVM address
        // Remove 0x prefix and take first 32 bytes after padding
        const cleaned = evmAddress.toLowerCase().replace('0x', '');
        // Pad with zeros to make it 64 chars (32 bytes)
        const padded = cleaned.padEnd(64, '0');
        return '0x' + padded.slice(0, 64);
    }

    /**
     * Get signer address
     */
    getSignerAddress(): string {
        return this.keypair.getPublicKey().toSuiAddress();
    }

    /**
     * Create a pre-funded wallet for Sui as source chain
     */
    async createWallet(
        orderHash: string,
        amount: bigint,
        tokenType: string = '0x2::sui::SUI'
    ): Promise<string> {
        console.log('Creating wallet with order hash:', orderHash);
        
        const tx = new Transaction();
        
        // Convert order hash to bytes array
        const orderHashBytes = Array.from(Buffer.from(orderHash.slice(2), 'hex'));
        
        // Split coin for funding
        const [coin] = tx.splitCoins(tx.gas, [amount]);
        
        // Call create_wallet entry function
        tx.moveCall({
            target: `${this.escrowPackageId}::escrow_create::create_wallet`,
            typeArguments: [tokenType],
            arguments: [
                tx.pure.vector('u8', orderHashBytes),
                coin,
                tx.object(SUI_CLOCK_OBJECT_ID)
            ]
        });
        
        // Execute transaction
        const result = await this.client.signAndExecuteTransaction({
            transaction: tx,
            signer: this.keypair,
            options: {
                showEffects: true,
                showEvents: true
            }
        });
        
        console.log('Transaction result:', result);
        
        // Extract wallet address from events
        const walletCreatedEvent = result.events?.find(
            e => e.type.includes('WalletCreated')
        );
        
        if (!walletCreatedEvent || !walletCreatedEvent.parsedJson) {
            throw new Error('Failed to create wallet - no event emitted');
        }
        
        const walletId = (walletCreatedEvent.parsedJson as any).wallet_id;
        console.log('✅ Wallet created at:', walletId);
        
        return walletId;
    }

    /**
     * Create source escrow on Sui (resolver pulls from wallet)
     */
    async createSrcEscrow(
        walletAddress: string,
        hashlock: string,
        taker: string, // EVM address
        amount: bigint,
        safetyDeposit: bigint,
        timelocks: {
            srcWithdrawal: number,
            srcPublicWithdrawal: number,
            srcCancellation: number,
            srcPublicCancellation: number,
            dstWithdrawal: number,
            dstPublicWithdrawal: number,
            dstCancellation: number
        },
        tokenType: string = '0x2::sui::SUI'
    ): Promise<string> {
        console.log('Creating source escrow...');
        
        const tx = new Transaction();
        
        // Split safety deposit from gas
        const [safetyDepositCoin] = tx.splitCoins(tx.gas, [safetyDeposit]);
        
        // Get current time in milliseconds
        const currentTime = Date.now();
        
        // Convert hashlock to bytes
        const hashlockBytes = Array.from(Buffer.from(hashlock.slice(2), 'hex'));
        
        // Convert taker EVM address to Sui format
        const takerSuiAddress = this.evmAddressToSuiAddress(taker);
        
        // Call create_escrow_src
        tx.moveCall({
            target: `${this.escrowPackageId}::escrow_create::create_escrow_src`,
            typeArguments: [tokenType],
            arguments: [
                tx.object(walletAddress),
                tx.pure.vector('u8', hashlockBytes),
                tx.pure.address(takerSuiAddress),
                tx.pure.u64(amount),
                safetyDepositCoin,
                // Timelocks (add to current time and convert to milliseconds)
                tx.pure.u64(currentTime + timelocks.srcWithdrawal * 1000),
                tx.pure.u64(currentTime + timelocks.srcPublicWithdrawal * 1000),
                tx.pure.u64(currentTime + timelocks.srcCancellation * 1000),
                tx.pure.u64(currentTime + timelocks.srcPublicCancellation * 1000),
                tx.pure.u64(currentTime + timelocks.dstWithdrawal * 1000),
                tx.pure.u64(currentTime + timelocks.dstPublicWithdrawal * 1000),
                tx.pure.u64(currentTime + timelocks.dstCancellation * 1000),
                tx.object(SUI_CLOCK_OBJECT_ID)
            ]
        });
        
        const result = await this.client.signAndExecuteTransaction({
            transaction: tx,
            signer: this.keypair,
            options: {
                showEffects: true,
                showEvents: true
            }
        });
        
        const escrowCreatedEvent = result.events?.find(
            e => e.type.includes('EscrowCreated')
        );
        
        if (!escrowCreatedEvent || !escrowCreatedEvent.parsedJson) {
            throw new Error('Failed to create escrow - no event emitted');
        }
        
        const escrowId = (escrowCreatedEvent.parsedJson as any).escrow_id;
        console.log('✅ Source escrow created at:', escrowId);
        
        return escrowId;
    }
}