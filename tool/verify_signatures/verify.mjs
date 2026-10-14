// Checks the in-app signer against real wallet code.
//
// flutter/tool/sign_vectors.dart signs one message on every chain family with
// the dev phrase. This script verifies each signature with the library that
// ecosystem's apps and wallets use, so a pass means our Dart signer produces
// exactly what MetaMask, Phantom, Slush, Keplr and NEAR wallets produce:
//
//   cd flutter && dart run tool/sign_vectors.dart > /tmp/vectors.json
//   cd ../tool/verify_signatures && npm ci && node verify.mjs /tmp/vectors.json
import { readFileSync } from 'node:fs';
import { verifyMessage } from 'viem';
import nacl from 'tweetnacl';
import bs58 from 'bs58';
import { verifyPersonalMessageSignature } from '@mysten/sui/verify';
import { verifyADR36Amino } from '@keplr-wallet/cosmos';
import { verifySignature } from '@near-wallet-selector/core';

const vectors = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const text = (s) => new TextEncoder().encode(s);
let failed = 0;
for (const v of vectors) {
  let ok = false;
  try {
    switch (v.family) {
      case 'evm':
        ok = await verifyMessage({ address: v.address, message: v.message, signature: v.signature });
        break;
      case 'solana':
        ok = nacl.sign.detached.verify(text(v.message), bs58.decode(v.signature), bs58.decode(v.address));
        break;
      case 'sui': {
        const key = await verifyPersonalMessageSignature(text(v.message), v.signature);
        ok = key.toSuiAddress() === v.address;
        break;
      }
      case 'cosmos':
        ok = verifyADR36Amino(
          'osmo',
          v.address,
          v.message,
          Buffer.from(v.publicKey, 'base64'),
          Buffer.from(v.signature, 'base64')
        );
        break;
      case 'near': {
        ok = verifySignature({
          publicKey: v.publicKey,
          signature: v.signature,
          message: v.message,
          nonce: Buffer.from(v.nonce, 'base64'),
          recipient: v.recipient,
        });
        // An implicit account ID is the hex of its ed25519 public key.
        ok &&= Buffer.from(bs58.decode(v.publicKey.slice(8))).toString('hex') === v.address;
        break;
      }
    }
  } catch (e) {
    console.log(`  ${v.family}: error ${e.message}`);
  }
  console.log(`${ok ? 'PASS' : 'FAIL'} ${v.family.padEnd(7)} ${v.address}`);
  if (!ok) failed++;
}
process.exit(failed ? 1 : 0);
