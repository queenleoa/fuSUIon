// tests/cross-chain-integration.spec.ts
import dotenv from 'dotenv';
dotenv.config();

import { createServer } from 'prool';
import { anvil } from 'prool/instances/anvil';
import { ethers, parseUnits, parseEther } from 'ethers';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { EVMWallet } from './evm-wallet';
import { SuiIntegration } from './sui-integration';
import { CrossChainOrderBuilder, ERC20_TOKENS } from './cross-chain-order-builder';

// Delay helper
const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

describe('Cross-Chain Swaps: EVM ↔ Sui', () => {
    let evmProvider: ethers.JsonRpcProvider;
    let evmNode: any;
    let userEvmWallet: EVMWallet;
    let resolverEvmWallet: EVMWallet;
    let suiUserIntegration: SuiIntegration;
    let suiResolverIntegration: SuiIntegration;
    
    beforeAll(async () => {
        console.log('🚀 Setting up test environment...\n');
        
        // 1. Start forked Ethereum mainnet
        console.log('1️⃣ Starting forked Ethereum mainnet...');
        evmNode = createServer({
            instance: anvil({
                forkUrl: 'https://eth.llamarpc.com',
                chainId: 1,
                forkBlockNumber: 19000000 // Recent block
            }),
            limit: 1
        });
        await evmNode.start();
        
        const address = evmNode.address();
        evmProvider = new ethers.JsonRpcProvider(
            `http://[${address.address}]:${address.port}/1`
        );
        console.log('✅ Forked mainnet running');
        
        // 2. Setup EVM wallets
        console.log('\n2️⃣ Setting up EVM wallets...');
        userEvmWallet = await EVMWallet.fromPrivateKey(
            process.env.USER_PRIVATE_KEY!,
            evmProvider
        );
        resolverEvmWallet = await EVMWallet.fromPrivateKey(
            process.env.RESOLVER_PRIVATE_KEY!,
            evmProvider
        );
        
        // Fund wallets with ETH
        const userAddress = await userEvmWallet.getAddress();
        const resolverAddress = await resolverEvmWallet.getAddress();
        
        await evmProvider.send('hardhat_setBalance', [
            userAddress,
            '0x' + parseEther('10').toString(16)
        ]);
        await evmProvider.send('hardhat_setBalance', [
            resolverAddress,
            '0x' + parseEther('10').toString(16)
        ]);
        console.log('✅ Wallets funded with ETH');
        
        // 3. Get USDC for testing
        console.log('\n3️⃣ Getting USDC from whale...');
        const USDC_WHALE = '0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa'; // Big USDC holder
        await evmProvider.send('hardhat_impersonateAccount', [USDC_WHALE]);
        
        const whaleSigner = await evmProvider.getSigner(USDC_WHALE);
        const usdcContract = new ethers.Contract(
            ERC20_TOKENS.ETHEREUM.USDC,
            ['function transfer(address to, uint256 amount) returns (bool)'],
            whaleSigner
        );
        
        // Transfer USDC to user
        await usdcContract.transfer(userAddress, parseUnits('1000', 6));
        console.log('✅ User received 1000 USDC');
        
        // 4. Setup Sui integration
        console.log('\n4️⃣ Setting up Sui integration...');
        const userKeypair = Ed25519Keypair.fromSecretKey(
            Buffer.from(process.env.USER_PRIVATE_KEY!.slice(2), 'hex').slice(0, 32)
        );
        const resolverKeypair = Ed25519Keypair.fromSecretKey(
            Buffer.from(process.env.RESOLVER_PRIVATE_KEY!.slice(2), 'hex').slice(0, 32)
        );
        
        suiUserIntegration = new SuiIntegration(
            process.env.SUI_RPC || 'https://fullnode.testnet.sui.io',
            process.env.SUI_ESCROW_PACKAGE_ID!,
            userKeypair
        );
        
        suiResolverIntegration = new SuiIntegration(
            process.env.SUI_RPC || 'https://fullnode.testnet.sui.io',
            process.env.SUI_ESCROW_PACKAGE_ID!,
            resolverKeypair
        );
        
        console.log('✅ All systems ready!\n');
    });
    
    afterAll(async () => {
        await evmNode?.stop();
        evmProvider?.destroy();
    });
    
    test('EVM (USDC) → Sui swap', async () => {
        console.log('=== Testing EVM USDC → Sui Swap ===\n');
        
        // Check initial balances
        const initialUSDC = await userEvmWallet.getTokenBalance(ERC20_TOKENS.ETHEREUM.USDC);
        const initialSuiBalance = await suiUserIntegration.getBalance(
            suiUserIntegration.getSignerAddress()
        );
        
        console.log('Initial balances:');
        console.log(`  User USDC: ${Number(initialUSDC) / 1e6}`);
        console.log(`  User SUI: ${Number(initialSuiBalance) / 1e9}`);
        
        // 1. Create order
        console.log('\n1️⃣ Creating cross-chain order...');
        const orderData = CrossChainOrderBuilder.createUSDCSwapOrder({
            direction: 'USDC_TO_SUI',
            evmChainId: CrossChainOrderBuilder.ETHEREUM_CHAIN_ID,
            usdcAmount: parseUnits('100', 6),  // 100 USDC
            suiAmount: BigInt(25 * 10**9),     // 25 SUI
            maker: await userEvmWallet.getAddress(),
            resolver: await resolverEvmWallet.getAddress(),
            escrowFactory: '0x0000000000000000000000000000000000000000' // Placeholder
        });
        
        console.log('Order created:');
        console.log(`  Order Hash: ${orderData.orderHash.slice(0, 10)}...`);
        console.log(`  Secret: ${orderData.secret.slice(0, 10)}...`);
        console.log(`  Hashlock: ${orderData.hashlock.slice(0, 10)}...`);
        
        // 2. User approves USDC
        console.log('\n2️⃣ User approving USDC...');
        await userEvmWallet.approveToken(
            ERC20_TOKENS.ETHEREUM.USDC,
            await resolverEvmWallet.getAddress(), // In production, this would be LOP
            parseUnits('100', 6)
        );
        
        // 3. Simulate order fill (transfer USDC to resolver)
        console.log('\n3️⃣ Simulating order fill...');
        const usdcAbi = ['function transfer(address to, uint256 amount) returns (bool)'];
        const usdcContract = new ethers.Contract(
            ERC20_TOKENS.ETHEREUM.USDC,
            usdcAbi,
            await userEvmWallet.signer
        );
        await usdcContract.transfer(
            await resolverEvmWallet.getAddress(),
            parseUnits('100', 6)
        );
        console.log('✅ USDC transferred to resolver');
        
        // 4. Create destination escrow on Sui
        console.log('\n4️⃣ Creating destination escrow on Sui...');
        const dstEscrowId = await suiResolverIntegration.createDstEscrow(
            orderData.orderHash,
            orderData.hashlock,
            await userEvmWallet.getAddress(),
            BigInt(25 * 10**9), // 25 SUI
            BigInt(110000000),  // 0.11 SUI safety deposit
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
        console.log(`✅ Destination escrow created: ${dstEscrowId}`);
        
        // 5. Wait for timelock and withdraw
        console.log('\n5️⃣ Waiting for timelock...');
        await delay(10000); // 10 seconds
        
        console.log('6️⃣ User withdrawing SUI...');
        await suiUserIntegration.withdraw(dstEscrowId, 'dst', orderData.secret);
        
        // Check final balances
        const finalUSDC = await userEvmWallet.getTokenBalance(ERC20_TOKENS.ETHEREUM.USDC);
        const finalSuiBalance = await suiUserIntegration.getBalance(
            suiUserIntegration.getSignerAddress()
        );
        
        console.log('\n✅ Swap complete!');
        console.log('Final balances:');
        console.log(`  User USDC: ${Number(finalUSDC) / 1e6} (-100)`);
        console.log(`  User SUI: ${Number(finalSuiBalance) / 1e9} (+~25)`);
        
        expect(Number(initialUSDC - finalUSDC)).toBe(100 * 1e6);
        expect(Number(finalSuiBalance)).toBeGreaterThan(Number(initialSuiBalance));
    }, 60000); // 60 second timeout
});