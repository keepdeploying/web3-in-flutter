// Prints the dev wallet's address on every chain, with faucet and explorer
// links. Run from the flutter/ folder:
//
//   dart run tool/addresses.dart
//
// It reads the public testnet recovery phrase in ../keys/dev-mnemonic.txt.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_counter/src/wallet/hd_keys.dart';

void main(List<String> args) {
  final file = File(args.isNotEmpty ? args.first : '../keys/dev-mnemonic.txt');
  final mnemonic = file.readAsStringSync().trim();
  if (!HdKeys.isValidMnemonic(mnemonic)) {
    stderr.writeln('Not a valid BIP-39 phrase: ${file.path}');
    exit(1);
  }

  final keys = HdKeys.deriveAll(mnemonic);
  String a(ChainFamily f) => keys[f]!.address;

  print('Dev wallet addresses (testnet only, the phrase is public)\n');
  for (final k in keys.values) {
    print('${k.family.name.padRight(7)} ${k.path.padRight(22)} ${k.address}');
  }

  print('\nExplorers');
  print('  Sepolia          https://sepolia.etherscan.io/address/${a(ChainFamily.evm)}');
  print('  Base Sepolia     https://sepolia.basescan.org/address/${a(ChainFamily.evm)}');
  print('  Arbitrum Sepolia https://sepolia.arbiscan.io/address/${a(ChainFamily.evm)}');
  print('  OP Sepolia       https://sepolia-optimism.etherscan.io/address/${a(ChainFamily.evm)}');
  print('  Solana devnet    https://explorer.solana.com/address/${a(ChainFamily.solana)}?cluster=devnet');
  print('  Sui testnet      https://suiscan.xyz/testnet/account/${a(ChainFamily.sui)}');
  print('  Osmosis testnet  https://celatone.osmosis.zone/osmo-test-5/accounts/${a(ChainFamily.cosmos)}');
  print('  NEAR testnet     https://testnet.nearblocks.io/address/${a(ChainFamily.near)}');
}
