import 'dart:convert';

import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/in_app_signer.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:flutter_test/flutter_test.dart';

const devPhrase = 'someone scrub boss million lesson spread strategy village hello excite celery silent';

/// The app's real signer against the real server code, on every network
/// and every sign-in level.
void main() {
  final keys = HdKeys.deriveAll(devPhrase);

  for (final network in Networks.all) {
    for (final level in SignInLevel.values) {
      test('${network.name}, level ${level.index + 1}: signs in, and replays behave as the level promises', () async {
        final server = CounterServer();
        final signer = InAppSigner(keys[network.family]!);
        final challenge = server.challenge(
          ChallengeRequest(level: level, family: network.family, address: signer.address, chainId: network.chainId),
        );
        final signed = await signer.signMessage(
          challenge.message,
          nearNonce: challenge.nearNonce == null ? null : base64Decode(challenge.nearNonce!),
        );

        final result = await server.signIn(signed, level: level, chainId: network.chainId);
        expect(result.ok, isTrue, reason: '${result.failure?.label}: ${result.failure?.detail}');
        expect(server.session(result.token).address, signer.address);

        final replay = await server.signIn(signed, level: level, chainId: network.chainId);
        expect(replay.ok, level == SignInLevel.fixed, reason: 'only level 1 accepts a replay');
      });
    }
  }
}
