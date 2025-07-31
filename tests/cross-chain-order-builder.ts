// tests/cross-chain-order-builder.ts - FIXED VERSION
import { randomBytes, keccak256 } from 'ethers';

// Import from 1inch SDK - checking different import styles
let Sdk: any;
try {
    Sdk = require('@1inch/cross-chain-sdk');
} catch (e) {
    console.error('Failed to import SDK:', e);
}

// Manual implementations if SDK imports fail
class SimpleLock {
    static hashSecret(secret: string): string {
        return keccak256(secret);
    }
    
    static forSingleFill(secret: string): any {
        return {
            hashlock: keccak256(secret),
            secret: secret
        };
    }
}

// Only ERC20 tokens supported by 1inch Limit Order Protocol
export const ERC20_TOKENS = {
    ETHEREUM: {
        USDC: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        USDT: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        DAI: '0x6B175474E89094C44Da98b954EedeAC495271d0F'
    },
    POLYGON: {
        USDC: '0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174',
        USDT: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
        DAI: '0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063'
    }
};

export class CrossChainOrderBuilder {
    static readonly ETHEREUM_CHAIN_ID = 1;
    static readonly POLYGON_CHAIN_ID = 137;
    static readonly SUI_CHAIN_ID = 101;
    
    /**
     * Create a simple order structure for cross-chain swaps
     */
    static createOrder(params: {
        direction: 'EVM_TO_SUI' | 'SUI_TO_EVM',
        evmChainId: number,
        erc20Token: 'USDC' | 'USDT' | 'DAI',
        erc20Amount: bigint,
        suiAmount: bigint,
        maker: string,
        resolver: string,
        escrowFactory: string
    }): {
        order: any
        orderHash: string
        secret: string
        hashlock: string
    } {
        // Generate secret
        const secretBytes = randomBytes(32);
        const secret = '0x' + Buffer.from(secretBytes).toString('hex');
        const hashlock = keccak256(secret);
        
        // Get ERC20 token address
        const tokens = params.evmChainId === this.ETHEREUM_CHAIN_ID 
            ? ERC20_TOKENS.ETHEREUM 
            : ERC20_TOKENS.POLYGON;
        const erc20Address = tokens[params.erc20Token];
        
        let srcChainId: number;
        let dstChainId: number;
        let makerAsset: string;
        let takerAsset: string;
        let makingAmount: bigint;
        let takingAmount: bigint;
        
        if (params.direction === 'EVM_TO_SUI') {
            srcChainId = params.evmChainId;
            dstChainId = this.SUI_CHAIN_ID;
            makerAsset = erc20Address;
            takerAsset = '0x0000000000000000000000000000000000000001';
            makingAmount = params.erc20Amount;
            takingAmount = params.suiAmount;
        } else {
            srcChainId = this.SUI_CHAIN_ID;
            dstChainId = params.evmChainId;
            makerAsset = '0x0000000000000000000000000000000000000002';
            takerAsset = erc20Address;
            makingAmount = params.suiAmount;
            takingAmount = params.erc20Amount;
        }
        
        // Create a simple order structure
        const order = {
            maker: params.maker,
            receiver: params.resolver,
            makerAsset,
            takerAsset,
            makingAmount: makingAmount.toString(),
            takingAmount: takingAmount.toString(),
            salt: Date.now().toString(),
            extension: {
                hashlock,
                srcChainId,
                dstChainId,
                srcSafetyDeposit: params.direction === 'EVM_TO_SUI' ? '1000000000000000' : '110000000',
                dstSafetyDeposit: params.direction === 'EVM_TO_SUI' ? '110000000' : '1000000000000000'
            }
        };
        
        // Simple order hash (in production, use proper EIP-712 hashing)
        const orderData = JSON.stringify(order);
        const orderHash = keccak256(Buffer.from(orderData));
        
        return {
            order,
            orderHash,
            secret,
            hashlock
        };
    }
    
    /**
     * Helper: Create USDC ↔ SUI swap order
     */
    static createUSDCSwapOrder(params: {
        direction: 'USDC_TO_SUI' | 'SUI_TO_USDC',
        evmChainId: number,
        usdcAmount: bigint,
        suiAmount: bigint,
        maker: string,
        resolver: string,
        escrowFactory: string
    }) {
        return this.createOrder({
            direction: params.direction === 'USDC_TO_SUI' ? 'EVM_TO_SUI' : 'SUI_TO_EVM',
            evmChainId: params.evmChainId,
            erc20Token: 'USDC',
            erc20Amount: params.usdcAmount,
            suiAmount: params.suiAmount,
            maker: params.maker,
            resolver: params.resolver,
            escrowFactory: params.escrowFactory
        });
    }
}