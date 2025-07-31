// tests/test-erc20-order.ts
import dotenv from 'dotenv';
dotenv.config();

import { CrossChainOrderBuilder } from './cross-chain-order-builder';
import { parseUnits } from 'ethers';

async function testERC20Order() {
    console.log('💰 Testing ERC20 Cross-Chain Orders\n');
    
    const maker = '0x742d35Cc6634C0532925a3b844Bc9e7595f5fF8B';
    const resolver = '0x2819c144D5946404C0516B6f817a960dB37D4929';
    const escrowFactory = '0x1234567890123456789012345678901234567890';
    
    // Test 1: USDC (Ethereum) → SUI
    console.log('1️⃣ USDC (Ethereum) → SUI');
    const usdcToSui = CrossChainOrderBuilder.createUSDCSwapOrder({
        direction: 'USDC_TO_SUI',
        evmChainId: CrossChainOrderBuilder.ETHEREUM_CHAIN_ID,
        usdcAmount: parseUnits('100', 6),      // 100 USDC
        suiAmount: BigInt(25 * 10**9),         // 25 SUI
        maker,
        resolver,
        escrowFactory
    });
    
    console.log('  Order Hash:', usdcToSui.orderHash.slice(0, 10) + '...');
    console.log('  Making: 100 USDC on Ethereum');
    console.log('  Taking: 25 SUI on Sui');
    
    // Test 2: SUI → USDC (Polygon)
    console.log('\n2️⃣ SUI → USDC (Polygon)');
    const suiToUsdc = CrossChainOrderBuilder.createUSDCSwapOrder({
        direction: 'SUI_TO_USDC',
        evmChainId: CrossChainOrderBuilder.POLYGON_CHAIN_ID,
        usdcAmount: parseUnits('100', 6),      // 100 USDC
        suiAmount: BigInt(25 * 10**9),         // 25 SUI
        maker,
        resolver,
        escrowFactory
    });
    
    console.log('  Order Hash:', suiToUsdc.orderHash.slice(0, 10) + '...');
    console.log('  Making: 25 SUI on Sui');
    console.log('  Taking: 100 USDC on Polygon');
    
    // Test 3: DAI (Ethereum) → SUI
    console.log('\n3️⃣ DAI (Ethereum) → SUI');
    const daiToSui = CrossChainOrderBuilder.createOrder({
        direction: 'EVM_TO_SUI',
        evmChainId: CrossChainOrderBuilder.ETHEREUM_CHAIN_ID,
        erc20Token: 'DAI',
        erc20Amount: parseUnits('100', 18),    // 100 DAI (18 decimals)
        suiAmount: BigInt(25 * 10**9),         // 25 SUI
        maker,
        resolver,
        escrowFactory
    });
    
    console.log('  Order Hash:', daiToSui.orderHash.slice(0, 10) + '...');
    console.log('  Making: 100 DAI on Ethereum');
    console.log('  Taking: 25 SUI on Sui');
    
    console.log('\n✅ ERC20 order tests complete!');
}

testERC20Order().catch(console.error);