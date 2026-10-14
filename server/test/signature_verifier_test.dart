import 'dart:convert';
import 'dart:io';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:test/test.dart';

/// Signatures from the app's in-app signer (flutter/tool/sign_vectors.dart),
/// each already verified by that chain's own JavaScript library
/// (tool/verify_signatures) and, for Sui, by a full node.
final fixtures = [
  for (final json in jsonDecode(File('test/fixtures/in_app_signatures.json').readAsStringSync()) as List)
    SignedMessage.fromJson(json as Map<String, dynamic>),
];

SignedMessage fixture(ChainFamily family) => fixtures.firstWhere((m) => m.family == family);

SignedMessage copy(SignedMessage m, {String? message, String? address, String? signature, String? recipient}) =>
    SignedMessage(
      family: m.family,
      address: address ?? m.address,
      message: message ?? m.message,
      signature: signature ?? m.signature,
      publicKey: m.publicKey,
      nonce: m.nonce,
      recipient: recipient ?? m.recipient,
    );

/// Answers every lookup with "yes", to test the paths that need the chain.
class AcceptingLookup implements ChainLookup {
  final calls = <String>[];

  @override
  Future<bool> erc1271IsValid({
    required String chainId,
    required String address,
    required List<int> hash,
    required List<int> signature,
  }) async {
    calls.add('erc1271 $chainId $address');
    return true;
  }

  @override
  Future<bool> nearHasFullAccessKey({required String accountId, required String publicKey}) async {
    calls.add('near $accountId');
    return true;
  }

  @override
  Future<bool> suiSignatureIsValid({
    required String message,
    required String signature,
    required String address,
  }) async {
    calls.add('sui $address');
    return true;
  }
}

void main() {
  final verifier = SignatureVerifier();

  for (final family in ChainFamily.values) {
    test('${family.label}: accepts a real signature', () async {
      final result = await verifier.verify(fixture(family));
      expect(result.valid, isTrue, reason: result.reason);
      expect(result.how, isNotEmpty);
    });

    test('${family.label}: rejects a changed message', () async {
      final result = await verifier.verify(copy(fixture(family), message: '${fixture(family).message}!'));
      expect(result.valid, isFalse);
      expect(result.reason, isNotEmpty);
    });

    test('${family.label}: rejects garbage without throwing', () async {
      final result = await verifier.verify(copy(fixture(family), signature: 'not a signature'));
      expect(result.valid, isFalse);
    });
  }

  test('EVM: rejects a signature from another account', () async {
    final result = await verifier.verify(
      copy(fixture(ChainFamily.evm), address: '0x9858EfFD232B4033E47d90003D41EC34EcaEda94'),
    );
    expect(result.valid, isFalse);
    expect(result.reason, contains('0xfFFAa29e82d5455985a908235536d2cD01aCce47'));
  });

  test('EVM: falls back to ERC-1271 for contract wallets', () async {
    final lookup = AcceptingLookup();
    final contractWallet = copy(fixture(ChainFamily.evm), address: '0x49f5A4DD302f5BA6F3414c7827428dbBe8E8D16d');
    final result = await SignatureVerifier(lookup: lookup).verify(contractWallet, evmChainId: '84532');
    expect(result.valid, isTrue);
    expect(lookup.calls, ['erc1271 84532 0x49f5A4DD302f5BA6F3414c7827428dbBe8E8D16d']);
    // Without a chain to ask, it stays invalid.
    expect((await SignatureVerifier(lookup: lookup).verify(contractWallet)).valid, isFalse);
  });

  test('Sui: rejects a key that does not match the address', () async {
    final result = await verifier.verify(copy(fixture(ChainFamily.sui), address: '0x${'1' * 64}'));
    expect(result.valid, isFalse);
    expect(result.reason, contains('belongs to'));
  });

  test('Sui: zkLogin signatures go to a full node', () async {
    final lookup = AcceptingLookup();
    final zk = copy(fixture(ChainFamily.sui), signature: base64Encode([SuiPersonalMessage.zkLoginFlag, 1, 2, 3]));
    expect((await SignatureVerifier(lookup: lookup).verify(zk)).valid, isTrue);
    expect(lookup.calls.single, startsWith('sui '));
  });

  test('Cosmos: rejects a high-S signature, even though the math checks out', () async {
    final m = fixture(ChainFamily.cosmos);
    final signature = base64Decode(m.signature);
    final n = Curves.generatorSecp256k1.order!;
    final highS = n - BigintUtils.fromBytes(signature.sublist(32));
    final flipped = base64Encode([...signature.sublist(0, 32), ...BigintUtils.toBytes(highS, length: 32)]);
    final result = await verifier.verify(copy(m, signature: flipped));
    expect(result.valid, isFalse);
    expect(result.reason, contains('High-S'));
  });

  test('NEAR: rejects a signature made for another app', () async {
    final result = await verifier.verify(copy(fixture(ChainFamily.near), recipient: 'evil.example'));
    expect(result.valid, isFalse);
    expect(result.reason, contains('evil.example'));
  });

  test('NEAR: a named account needs the chain to confirm the key', () async {
    final named = copy(fixture(ChainFamily.near), address: 'someone.testnet');
    expect((await verifier.verify(named)).valid, isFalse);
    final lookup = AcceptingLookup();
    expect((await SignatureVerifier(lookup: lookup).verify(named)).valid, isTrue);
    expect(lookup.calls, ['near someone.testnet']);
  });
}
