// tests/check-sui-exports.ts
console.log('Checking Sui SDK exports...\n');

// Check client exports
import * as clientExports from '@mysten/sui/client';
console.log('Client exports:', Object.keys(clientExports).slice(0, 10), '...');

// Check transaction exports
import * as txExports from '@mysten/sui/transactions';
console.log('\nTransaction exports:', Object.keys(txExports));

// Check keypair exports
import * as keypairExports from '@mysten/sui/keypairs/ed25519';
console.log('\nEd25519 Keypair exports:', Object.keys(keypairExports));