// Signs in to a running server with the dev recovery phrase, on every
// network and level, and prints each check. Start the server first:
//
//   cd server && dart run bin/server.dart
//   cd flutter && dart run tool/try_sign_in.dart [http://localhost:8080]
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_counter/src/backend/backend.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/in_app_signer.dart';

Future<void> main(List<String> args) async {
  final backend = HttpBackend(Uri.parse(args.isEmpty ? 'http://localhost:8080' : args.first));
  print('Server: ${jsonEncode(await backend.health())}\n');
  final keys = HdKeys.deriveAll(File('../keys/dev-mnemonic.txt').readAsStringSync());
  var failures = 0;

  for (final network in Networks.all) {
    for (final level in SignInLevel.values) {
      final signer = InAppSigner(keys[network.family]!);
      final challenge = await backend.challenge(
        ChallengeRequest(level: level, family: network.family, address: signer.address, chainId: network.chainId),
      );
      final signed = await signer.signMessage(
        challenge.message,
        nearNonce: challenge.nearNonce == null ? null : base64Decode(challenge.nearNonce!),
      );
      final result = await backend.signIn(signed, level: level, chainId: network.chainId);
      final replay = await backend.signIn(signed, level: level, chainId: network.chainId);
      final expectedReplay = level == SignInLevel.fixed;
      final ok = result.ok && replay.ok == expectedReplay;
      if (!ok) failures++;
      print(
        '${ok ? 'OK  ' : 'FAIL'} ${network.name.padRight(17)} level ${level.index + 1}: '
        'sign-in ${result.ok ? 'accepted' : 'refused (${result.failure?.label})'}, '
        'replay ${replay.ok ? 'accepted' : 'refused (${replay.failure?.label})'}',
      );
      if (result.ok && network == Networks.sepolia) {
        await backend.setDescription(result.token!, 'gm from the dev wallet, level ${level.index + 1}');
      }
    }
  }
  print('\nDescriptions: ${(await backend.descriptions()).map((d) => d.text).join(' | ')}');
  exit(failures == 0 ? 0 : 1);
}
