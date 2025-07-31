// tests/evm-resolver.ts
import { ethers, ContractFactory } from 'ethers';
import Sdk from '@1inch/cross-chain-sdk';
import { IOrderMixin } from '@1inch/cross-chain-sdk';

// Import contract artifacts from your cross-chain-resolver-example
import ResolverArtifact from '../contracts/dist/contracts/Resolver.sol/Resolver.json';
import EscrowFactoryArtifact from '../contracts/dist/contracts/TestEscrowFactory.sol/TestEscrowFactory.json';

export interface EVMContracts {
    escrowFactory: string;
    resolver: string;
    limitOrderProtocol: string;
}

export class EVMResolver {
    private resolverContract: ethers.Contract;
    private escrowFactory: ethers.Contract;
    private limitOrderProtocol: ethers.Contract;
    
    constructor(
        private contracts: EVMContracts,
        private signer: ethers.Signer
    ) {
        // Initialize contracts
        this.resolverContract = new ethers.Contract(
            contracts.resolver,
            ResolverArtifact.abi,
            signer
        );
        
        this.escrowFactory = new ethers.Contract(
            contracts.escrowFactory,
            EscrowFactoryArtifact.abi,
            signer
        );
        
        // 1inch Limit Order Protocol ABI (simplified)
        const lopAbi = [
            'function fillOrderArgs(tuple(uint256 salt, address maker, address receiver, address makerAsset, address takerAsset, uint256 makingAmount, uint256 takingAmount, bytes extension) order, bytes32 r, bytes32 vs, uint256 amount, uint256 takerTraits, bytes args)',
            'event OrderFilled(bytes32 indexed orderHash, uint256 makingAmount)'
        ];
        
        this.limitOrderProtocol = new ethers.Contract(
            contracts.limitOrderProtocol,
            lopAbi,
            signer
        );
    }
    
    /**
     * Deploy contracts on forked mainnet
     */
    static async deployContracts(signer: ethers.Signer): Promise<EVMContracts> {
        console.log('Deploying EVM contracts...');
        
        // 1inch LOP is already deployed on mainnet
        const limitOrderProtocol = '0x111111125421ca6dc452d289314280a0f8842a65';
        
        // Deploy EscrowFactory
        const factoryFactory = new ContractFactory(
            EscrowFactoryArtifact.abi,
            EscrowFactoryArtifact.bytecode,
            signer
        );
        
        const escrowFactory = await factoryFactory.deploy(
            limitOrderProtocol,
            '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2', // WETH
            ethers.ZeroAddress, // No access token
            await signer.getAddress(),
            1800, // 30 min rescue delay
            1800
        );
        await escrowFactory.waitForDeployment();
        
        // Deploy Resolver
        const resolverFactory = new ContractFactory(
            ResolverArtifact.abi,
            ResolverArtifact.bytecode,
            signer
        );
        
        const resolver = await resolverFactory.deploy(
            await escrowFactory.getAddress(),
            limitOrderProtocol,
            await signer.getAddress()
        );
        await resolver.waitForDeployment();
        
        return {
            escrowFactory: await escrowFactory.getAddress(),
            resolver: await resolver.getAddress(),
            limitOrderProtocol
        };
    }
    
    /**
     * Fill order and create source escrow (following cross-chain-resolver-example)
     */
    async fillOrderAndCreateSrcEscrow(
        order: any,
        signature: string,
        amount: bigint,
        immutables: any
    ): Promise<string> {
        console.log('Filling order and creating source escrow...');
        
        // This follows the deploySrc pattern from cross-chain-resolver-example
        const tx = await this.resolverContract.deploySrc(
            immutables,
            order,
            signature.slice(0, 66), // r
            '0x' + signature.slice(66), // vs
            amount,
            0, // TakerTraits (default)
            '0x', // empty args
            {
                value: immutables.safetyDeposit
            }
        );
        
        const receipt = await tx.wait();
        console.log('✅ Order filled, tx:', receipt.hash);
        
        // Get escrow address from events
        const srcEscrowCreatedEvent = receipt.logs.find(
            (log: any) => log.topics[0] === ethers.id('SrcEscrowCreated(address,(bytes32,bytes32,address,address,address,uint256,uint256,uint256),(address,uint256,address,uint256))')
        );
        
        if (!srcEscrowCreatedEvent) {
            throw new Error('Failed to find SrcEscrowCreated event');
        }
        
        // Decode event to get escrow address
        const escrowAddress = '0x' + srcEscrowCreatedEvent.topics[1].slice(26);
        return escrowAddress;
    }
}