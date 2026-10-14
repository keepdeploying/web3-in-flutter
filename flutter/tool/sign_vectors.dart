// Signs one message with the dev recovery phrase on every chain family and
// prints the results as JSON. tool/verify_signatures/ checks them with each
// ecosystem's own libraries (viem, tweetnacl, Mysten's Sui SDK, Keplr and
// NEAR Wallet Selector), which is how we know our signer matches real wallets:
//
//   dart run tool/sign_vectors.dart > /tmp/vectors.json
//   cd ../tool/verify_signatures && npm ci && node verify.mjs /tmp/vectors.json
//
// The NEAR nonce is fixed (bytes 0 to 31) so the output is the same on every
// run. Every other scheme is deterministic already.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/in_app_signer.dart';

Future<void> main(List<String> args) async {
  final phrase = File('../keys/dev-mnemonic.txt').readAsStringSync().trim();
  final message = args.isNotEmpty
      ? args.first
      : 'Sign in to Flutter Counter\n\nNonce: 7Hq2k9Xa\nUnicode check: café, 你好';
  final keys = HdKeys.deriveAll(phrase);
  final out = [
    for (final key in keys.values)
      (await InAppSigner(key, nonce: () => List.generate(32, (i) => i)).signMessage(message)).toJson(),
  ];
  print(const JsonEncoder.withIndent('  ').convert(out));
}
