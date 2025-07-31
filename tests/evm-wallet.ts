// tests/evm-wallet.ts
import { ethers, Signer, TransactionRequest } from 'ethers';

export class EVMWallet {
    constructor(
        public signer: Signer,
        public provider: ethers.JsonRpcProvider
    ) {}
    
    static async fromPrivateKey(privateKey: string, provider: ethers.JsonRpcProvider): Promise<EVMWallet> {
        const wallet = new ethers.Wallet(privateKey, provider);
        return new EVMWallet(wallet, provider);
    }
    
    async getAddress(): Promise<string> {
        return this.signer.getAddress();
    }
    
    async getBalance(): Promise<bigint> {
        const address = await this.getAddress();
        return this.provider.getBalance(address);
    }
    
    async getTokenBalance(tokenAddress: string): Promise<bigint> {
        const abi = ['function balanceOf(address) view returns (uint256)'];
        const contract = new ethers.Contract(tokenAddress, abi, this.provider);
        return contract.balanceOf(await this.getAddress());
    }
    
    async approveToken(tokenAddress: string, spender: string, amount: bigint): Promise<void> {
        const abi = ['function approve(address spender, uint256 amount) returns (bool)'];
        const contract = new ethers.Contract(tokenAddress, abi, this.signer);
        const tx = await contract.approve(spender, amount);
        await tx.wait();
        console.log(`✅ Approved ${amount} tokens to ${spender}`);
    }
    
    async sendTransaction(tx: TransactionRequest): Promise<ethers.TransactionReceipt> {
        const response = await this.signer.sendTransaction(tx);
        const receipt = await response.wait();
        if (!receipt || receipt.status !== 1) {
            throw new Error('Transaction failed');
        }
        return receipt;
    }
}