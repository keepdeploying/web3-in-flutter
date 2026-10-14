import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter/src/wallet/installed/mobile/nacl_box.dart';
import 'package:flutter_test/flutter_test.dart';

// Vectors from TweetNaCl (`nacl.box`), the library Phantom and Solflare use.
final aSecret = List.generate(32, (i) => i + 1);
final bSecret = List.generate(32, (i) => 200 - i);
final nonce = List.generate(24, (i) => i * 7 % 256);
const aPublic = '07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c';
const bPublic = '8dafcfeeae9045ee9a78d78a99fcf32e7781e441eb073096c342b8e2dcc3b612';
const sealedHello = '0bbd7ca2fcf1db28f704a2ea076eb76d35c8bea348';
const sealed100 =
    '87d53af55b6633f215476d6676b72af825d5aab75f610c5041f21be96de5b46b76e151f275252f7fbaada2c69e0d0fead14da9397'
    '226c66e40fe13f5982dfa3a355b1c6e8ac69509a9e51e8a0a57b5264e3890b02ecc19e319f1c2f7006909f79c923869ce9646a63d8'
    '0a6c7fb4ae3b811115138';

void main() {
  test('derives the same public keys as TweetNaCl', () {
    expect(BytesUtils.toHexString(X25519.scalarMultBase(aSecret).publicKey), aPublic);
    expect(BytesUtils.toHexString(X25519.scalarMultBase(bSecret).publicKey), bPublic);
  });

  test('seals exactly what nacl.box seals, across more than one 64-byte block', () {
    final box = NaclBox.between(aSecret, BytesUtils.fromHexString(bPublic));
    expect(BytesUtils.toHexString(box.seal(utf8.encode('hello'), nonce)), sealedHello);
    expect(BytesUtils.toHexString(box.seal(utf8.encode('x' * 100), nonce)), sealed100);
  });

  test('the other side opens it, and a changed byte is refused', () {
    final box = NaclBox.between(bSecret, BytesUtils.fromHexString(aPublic));
    expect(utf8.decode(box.open(BytesUtils.fromHexString(sealed100), nonce)!), 'x' * 100);

    final tampered = BytesUtils.fromHexString(sealedHello)..[20] ^= 1;
    expect(box.open(tampered, nonce), isNull);
  });
}
