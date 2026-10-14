@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:test/test.dart';

void main() {
  final lookup = RpcChainLookup();
  final fixtures = [
    for (final json in jsonDecode(File('test/fixtures/in_app_signatures.json').readAsStringSync()) as List)
      SignedMessage.fromJson(json as Map<String, dynamic>),
  ];
  SignedMessage fixture(ChainFamily family) => fixtures.firstWhere((m) => m.family == family);

  test('a Sui full node accepts our signature', () async {
    final m = fixture(ChainFamily.sui);
    expect(await lookup.suiSignatureIsValid(message: m.message, signature: m.signature, address: m.address), isTrue);
    expect(
      await lookup.suiSignatureIsValid(message: '${m.message}!', signature: m.signature, address: m.address),
      isFalse,
    );
  });

  test('NEAR confirms the dev key is a full-access key of its account', () async {
    final m = fixture(ChainFamily.near);
    expect(await lookup.nearHasFullAccessKey(accountId: m.address, publicKey: m.publicKey!), isTrue);
    expect(
      await lookup.nearHasFullAccessKey(accountId: m.address, publicKey: 'ed25519:11111111111111111111111111111111'),
      isFalse,
    );
  });

  test('ERC-1271 says no for a plain account (no contract code)', () async {
    final m = fixture(ChainFamily.evm);
    expect(
      await lookup.erc1271IsValid(chainId: '11155111', address: m.address, hash: List.filled(32, 1), signature: [1]),
      isFalse,
    );
  });
}
