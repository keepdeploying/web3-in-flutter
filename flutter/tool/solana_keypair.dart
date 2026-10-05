// Writes the dev wallet's Solana key as a Solana CLI keypair file (a JSON
// array of 64 bytes: the 32-byte secret key followed by the 32-byte public
// key). Anchor and the Solana CLI use this file to deploy and pay fees.
//
// Run from the flutter/ folder:
//
//   dart run tool/solana_keypair.dart ../keys/solana-dev-keypair.json
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_counter/src/wallet/hd_keys.dart';

void main(List<String> args) {
  final out = File(args.isNotEmpty ? args.first : '../keys/solana-dev-keypair.json');
  final mnemonic = File('../keys/dev-mnemonic.txt').readAsStringSync().trim();
  final key = HdKeys.derive(HdKeys.seedFrom(mnemonic), ChainFamily.solana);
  out.writeAsStringSync(jsonEncode([...key.privateKey, ...key.publicKey]));
  print('Wrote ${out.path} for ${key.address}');
}
