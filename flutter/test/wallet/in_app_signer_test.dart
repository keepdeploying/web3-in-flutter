import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/in_app_signer.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// The repo's dev phrase (keys/dev-mnemonic.txt). Public on purpose, testnets only.
const devPhrase = 'someone scrub boss million lesson spread strategy village hello excite celery silent';

const message = 'Sign in to Flutter Counter\n\nNonce: 7Hq2k9Xa\nUnicode check: café, 你好';

void main() {
  final keys = HdKeys.deriveAll(devPhrase);

  InAppSigner signer(ChainFamily family) => InAppSigner(keys[family]!, nonce: () => List.generate(32, (i) => i));

  // Each signature below was verified with that ecosystem's own library
  // (tool/verify_signatures): viem, tweetnacl, @mysten/sui, @keplr-wallet/cosmos
  // and @near-wallet-selector/core. The schemes are deterministic, so any
  // change to our signer that breaks compatibility changes these bytes.
  const expected = {
    ChainFamily.evm: '0xba0eaad8881d4116a4f8c2f499e63042280202bbe099c7699f873edac86cd2e13d235c065e827fe5167a57f7d78e92c739efbd01356c01d6074ca352d5da51751b',
    ChainFamily.solana: '2JMUjRmkaDYrarZpMSqVquSyv2J1vXASYVcdiCUavj592YpRZ7MHeSS9xKHxStT3P359DzxLHmF3awVH3QdZakRW',
    ChainFamily.sui: 'AJW4hoNG27ZUHgIYgDYYAcxafJLjVc4r5rgar6hI5cm6HepA1oCgegYwl75Q+m+AiPQmehTy3STF3ExUgR8oYAAdWCtzTT5WmO6UR2/Q3S7+582/0mXyCiEOfUNNIfgV3Q==',
    ChainFamily.cosmos: 'Sey7vdRSlX50Qz6Qzxk+LdW5aQwdENiYPafXJNBmlc8r0VKfUyzCN2SDw7ki5ugNX8aQtmDnA58nnwioGtvjJw==',
    ChainFamily.near: 'fUx9XCxhvgbU6upS0b5mlJ/K5igU9pY2qdXMElaZ/dQYIKcqHl6T8/ttyzQm33QWBoCYTweeR/yrenvWBrsFDw==',
  };

  for (final family in ChainFamily.values) {
    test('${family.label} signature matches what real wallet libraries verify', () async {
      final signed = await signer(family).signMessage(message);
      expect(signed.signature, expected[family]);
      expect(signed.address, keys[family]!.address);
    });
  }

  test('EIP-191 hash matches viem hashMessage', () {
    expect(
      BytesUtils.toHexString(Eip191.hash('hello world'), prefix: '0x'),
      '0xd9eba16ed0ecae432b71fe008c98cc872bb4cc214d3220a36f365326cf807d68',
    );
  });

  test('NEAR signatures carry the key, nonce and recipient the verifier needs', () async {
    final signed = await signer(ChainFamily.near).signMessage(message);
    expect(signed.publicKey, startsWith('ed25519:'));
    expect(base64Decode(signed.nonce!), List.generate(32, (i) => i));
    expect(signed.recipient, 'flutter-counter.app');
    // The random default gives a different nonce every time.
    final a = await InAppSigner(keys[ChainFamily.near]!).signMessage(message);
    final b = await InAppSigner(keys[ChainFamily.near]!).signMessage(message);
    expect(a.nonce, isNot(b.nonce));
  });

  test('Cosmos signatures are low-S', () {
    final n = Curves.generatorSecp256k1.order!;
    final high = [...List.filled(32, 1), ...BigintUtils.toBytes(n - BigInt.one, length: 32)];
    expect(BigintUtils.fromBytes(InAppSigner.lowS(high).sublist(32)), BigInt.one);
  });

  test('refuses an empty message', () {
    expect(signer(ChainFamily.evm).signMessage(''), throwsArgumentError);
  });

  test('SignedMessage survives a JSON round trip', () async {
    final signed = await signer(ChainFamily.near).signMessage(message);
    final copy = SignedMessage.fromJson(jsonDecode(jsonEncode(signed.toJson())) as Map<String, dynamic>);
    expect(copy.toJson(), signed.toJson());
  });

  test('ULEB128 lengths match the BCS spec', () {
    expect(uleb128(0), [0]);
    expect(uleb128(127), [0x7f]);
    expect(uleb128(128), [0x80, 0x01]);
    expect(uleb128(300), [0xac, 0x02]);
  });
}
