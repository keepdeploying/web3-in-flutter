/// How each chain turns a text message into the bytes a wallet signs.
///
/// Wallets never sign your text as-is. Each chain wraps it first, so a
/// signed message can never be mistaken for a signed transaction. The app's
/// in-app signer uses these to sign, and the backend uses the same code to
/// verify, so both sides always agree on the bytes.
///
/// | Chain   | Standard                   | What gets signed                                  |
/// | ------- | -------------------------- | ------------------------------------------------- |
/// | EVM     | EIP-191 (`personal_sign`)  | keccak256 of a prefix, the length and the text    |
/// | Solana  | Wallet Standard signMessage | the UTF-8 text itself                            |
/// | Sui     | personal message intent    | blake2b-256 of an intent and the BCS-encoded text |
/// | Cosmos  | ADR-36                     | sha256 of an Amino JSON "sign doc"                |
/// | NEAR    | NEP-413                    | sha256 of a tag and a Borsh-encoded payload       |
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

/// EIP-191 version 0x45 ("E"), what MetaMask's `personal_sign` signs.
abstract final class Eip191 {
  /// The 32-byte hash that the secp256k1 key signs:
  /// `keccak256("\x19Ethereum Signed Message:\n" + byteLength + message)`.
  static List<int> hash(String message) {
    final bytes = utf8.encode(message);
    return QuickCrypto.keccack256Hash([...utf8.encode('\x19Ethereum Signed Message:\n${bytes.length}'), ...bytes]);
  }
}

/// Solana wallets (Phantom, Solflare, the Wallet Standard `signMessage`)
/// sign the raw message bytes with ed25519. There is no prefix: wallets
/// instead refuse to sign anything that parses as a transaction.
abstract final class SolanaMessage {
  static List<int> bytes(String message) => utf8.encode(message);
}

/// Sui's personal message signing, as in `signPersonalMessage`.
abstract final class SuiPersonalMessage {
  /// Intent scope 3 (PersonalMessage), version 0, app ID 0 (Sui).
  static const intent = [3, 0, 0];

  /// Signature scheme flags in Sui's serialized signatures. Wallets made
  /// from a recovery phrase use ed25519; zkLogin (sign in with Google and
  /// others) has its own, much longer format.
  static const ed25519Flag = 0x00;
  static const secp256k1Flag = 0x01;
  static const zkLoginFlag = 0x05;

  /// The 32-byte digest the key signs: blake2b-256 of the intent
  /// followed by the message as BCS `vector<u8>` (a ULEB128 length, then
  /// the bytes).
  static List<int> digest(String message) {
    final bytes = utf8.encode(message);
    return QuickCrypto.blake2b256Hash([...intent, ...uleb128(bytes.length), ...bytes]);
  }

  /// Sui's serialized signature: flag, signature and public key, base64.
  /// This is the string wallets return and verifiers expect.
  static String serialize(List<int> signature, List<int> publicKey) =>
      base64Encode([ed25519Flag, ...signature, ...publicKey]);

  /// Splits a serialized ed25519 or secp256k1 signature into its parts:
  /// flag (1 byte), signature (64 bytes) and public key (32 or 33 bytes).
  static ({int flag, List<int> signature, List<int> publicKey}) parse(String serialized) {
    final bytes = base64Decode(serialized);
    final keyLength = switch (bytes.isEmpty ? -1 : bytes[0]) {
      ed25519Flag => 32,
      secp256k1Flag => 33,
      final flag => throw FormatException('Unsupported Sui signature scheme (flag $flag)'),
    };
    if (bytes.length != 1 + 64 + keyLength) throw FormatException('Expected ${1 + 64 + keyLength} bytes');
    return (flag: bytes[0], signature: bytes.sublist(1, 65), publicKey: bytes.sublist(65));
  }

  /// A Sui address: blake2b-256 of the scheme flag and the public key.
  static String address(int flag, List<int> publicKey) =>
      BytesUtils.toHexString(QuickCrypto.blake2b256Hash([flag, ...publicKey]), prefix: '0x');
}

/// ADR-36, how Keplr and Leap sign arbitrary data (`signArbitrary`).
///
/// The data goes inside a fake Amino transaction with an empty chain ID,
/// zero fees and a `sign/MsgSignData` message. A real chain would never
/// accept it, which is the point.
abstract final class Adr36 {
  /// The sign doc as canonical JSON: keys sorted, no spaces.
  static String signDoc({required String signer, required String message}) => jsonEncode({
    'account_number': '0',
    'chain_id': '',
    'fee': {'amount': <Object>[], 'gas': '0'},
    'memo': '',
    'msgs': [
      {
        'type': 'sign/MsgSignData',
        'value': {'data': base64Encode(utf8.encode(message)), 'signer': signer},
      },
    ],
    'sequence': '0',
  });

  /// The 32-byte digest the secp256k1 key signs: sha256 of the sign doc.
  static List<int> digest({required String signer, required String message}) =>
      QuickCrypto.sha256Hash(utf8.encode(signDoc(signer: signer, message: message)));
}

/// NEP-413, how NEAR wallets sign messages (`signMessage`).
abstract final class Nep413 {
  /// 2^31 + 413. The high bit puts the tag outside the range of any valid
  /// transaction's first field, so a signed message is never a transaction.
  static const tag = 2147484061;

  /// The Borsh-encoded payload: message (string), nonce ([u8; 32]),
  /// recipient (string) and callbackUrl (`Option<string>`).
  static List<int> payload({
    required String message,
    required List<int> nonce,
    required String recipient,
    String? callbackUrl,
  }) {
    if (nonce.length != 32) throw ArgumentError.value(nonce.length, 'nonce', 'must be 32 bytes');
    return [
      ..._borshString(message),
      ...nonce,
      ..._borshString(recipient),
      if (callbackUrl == null) 0 else ...[1, ..._borshString(callbackUrl)],
    ];
  }

  /// The 32-byte hash the ed25519 key signs: sha256 of the tag (u32, little
  /// endian) followed by the payload.
  static List<int> hash({
    required String message,
    required List<int> nonce,
    required String recipient,
    String? callbackUrl,
  }) => QuickCrypto.sha256Hash([
    ..._u32(tag),
    ...payload(message: message, nonce: nonce, recipient: recipient, callbackUrl: callbackUrl),
  ]);

  static List<int> _borshString(String value) {
    final bytes = utf8.encode(value);
    return [..._u32(bytes.length), ...bytes];
  }
}

List<int> _u32(int value) => (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

/// Unsigned LEB128: 7 bits per byte, low bits first, high bit set on every
/// byte but the last. BCS uses it for lengths.
List<int> uleb128(int value) {
  final out = <int>[];
  do {
    var byte = value & 0x7f;
    value >>= 7;
    if (value != 0) byte |= 0x80;
    out.add(byte);
  } while (value != 0);
  return out;
}
