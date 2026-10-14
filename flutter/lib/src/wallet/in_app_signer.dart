import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';

import 'hd_keys.dart';
import 'wallet_signer.dart';

/// Signs with a private key the app holds itself (branch A, "be the wallet").
///
/// It does exactly what a wallet app does when you approve a request: wrap
/// the message in the chain's format, hash it, and sign the hash with the
/// key. The wrapping lives in the server package, so the backend checks the
/// very same bytes.
class InAppSigner implements WalletSigner {
  InAppSigner(this.key, {this.recipient = defaultRecipient, List<int> Function()? nonce})
    : _nonce = nonce ?? (() => QuickCrypto.generateRandom(32));

  final ChainKey key;

  /// NEP-413's `recipient`: who the NEAR message is for. Wallets show it, and
  /// the backend checks it, so a signature for one app can't be used on
  /// another.
  final String recipient;

  static const defaultRecipient = 'flutter-counter.app';

  // The library's signer objects, made once: setting up a secp256k1 signer
  // costs more than signing with it.
  late final _ethSigner = ETHSigner.fromKeyBytes(key.privateKey);
  late final _secpSigner = Secp256k1Signer.fromKeyBytes(key.privateKey);
  late final _edSigner = Ed25519Signer.fromKeyBytes(key.privateKey);

  /// Makes NEP-413 nonces. Random by default; tests pass a fixed one.
  final List<int> Function() _nonce;

  @override
  ChainFamily get family => key.family;

  @override
  String get address => key.address;

  @override
  String get name => 'In-app wallet';

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    // Wallets refuse empty messages, and ADR-36 forbids them outright.
    if (message.isEmpty) throw ArgumentError.value(message, 'message', 'Nothing to sign');
    switch (family) {
      case ChainFamily.evm:
        // ETHSigner returns r, s and v (27 or 28). v lets the verifier
        // recover the public key, and from it the address.
        final signature = _ethSigner.sign(Eip191.hash(message), hashMessage: false);
        return _signed(message, BytesUtils.toHexString(signature.toBytes(), prefix: '0x'));

      case ChainFamily.solana:
        final signature = _edSigner.sign(SolanaMessage.bytes(message));
        return _signed(message, Base58Encoder.encode(signature));

      case ChainFamily.sui:
        final signature = _edSigner.sign(SuiPersonalMessage.digest(message));
        return _signed(message, SuiPersonalMessage.serialize(signature, key.publicKey));

      case ChainFamily.cosmos:
        final digest = Adr36.digest(signer: address, message: message);
        final signature = lowS(_secpSigner.sign(digest, hashMessage: false));
        return _signed(message, base64Encode(signature), publicKey: base64Encode(key.publicKey));

      case ChainFamily.near:
        // A fresh random nonce per message. The backend remembers used
        // nonces, so the same signature can't be replayed.
        final nonce = nearNonce ?? _nonce();
        final hash = Nep413.hash(message: message, nonce: nonce, recipient: recipient);
        final signature = _edSigner.sign(hash);
        return _signed(
          message,
          base64Encode(signature),
          publicKey: 'ed25519:${Base58Encoder.encode(key.publicKey)}',
          nonce: base64Encode(nonce),
          recipient: recipient,
        );
    }
  }

  SignedMessage _signed(String message, String signature, {String? publicKey, String? nonce, String? recipient}) =>
      SignedMessage(
        family: family,
        address: address,
        message: message,
        signature: signature,
        publicKey: publicKey,
        nonce: nonce,
        recipient: recipient,
      );

  // Raw signing, for transactions. Each chain decides what to hash; these
  // only apply the key. A wallet app runs the same three operations when
  // you approve a transaction.

  /// secp256k1 over a 32-byte hash, with the recovery id (EVM).
  ETHSignature signEvmHash(List<int> hash) => _ethSigner.sign(hash, hashMessage: false);

  /// secp256k1 over a 32-byte digest, low-S, 64 bytes (Cosmos).
  List<int> signSecp256k1(List<int> digest) => lowS(_secpSigner.sign(digest, hashMessage: false));

  /// ed25519 over any bytes (Solana, Sui, NEAR).
  List<int> signEd25519(List<int> message) => _edSigner.sign(message);

  /// Cosmos only accepts "low-S" signatures: of the two valid values for s
  /// (s and n - s), the smaller one. This makes signatures non-malleable.
  static List<int> lowS(List<int> signature) {
    final n = Curves.generatorSecp256k1.order!;
    final s = BigintUtils.fromBytes(signature.sublist(32));
    if (s <= n >> 1) return signature;
    return [...signature.sublist(0, 32), ...BigintUtils.toBytes(n - s, length: 32)];
  }
}
