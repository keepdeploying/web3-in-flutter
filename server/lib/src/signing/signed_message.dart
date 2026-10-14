import '../chain_family.dart';

/// A signed text message, in the form each chain's wallets return it.
///
/// This is what the app sends to the backend to sign in. Every field is a
/// string so it travels as JSON unchanged.
class SignedMessage {
  const SignedMessage({
    required this.family,
    required this.address,
    required this.message,
    required this.signature,
    this.publicKey,
    this.nonce,
    this.recipient,
  });

  final ChainFamily family;

  /// The account that claims to have signed.
  final String address;

  /// The exact text that was signed.
  final String message;

  /// The signature, encoded the way the chain's wallets return it:
  /// - EVM: 0x-prefixed hex, 65 bytes (r, s, v);
  /// - Solana: base58, 64 bytes;
  /// - Sui: base64 serialized signature (flag, signature, public key);
  /// - Cosmos: base64, 64 bytes (r, s);
  /// - NEAR: base64, 64 bytes.
  final String signature;

  /// The public key, for chains where the verifier can't get it from the
  /// address or the signature:
  /// - Cosmos: base64 compressed secp256k1 key (the address is only a hash of it);
  /// - NEAR: `ed25519:` plus base58 (an account can have many keys).
  ///
  /// EVM recovers the key from the signature, a Solana address is the key,
  /// and Sui puts the key inside the serialized signature.
  final String? publicKey;

  /// NEAR only (NEP-413): the 32-byte nonce, base64.
  final String? nonce;

  /// NEAR only (NEP-413): who the message is for, usually the app's domain.
  final String? recipient;

  Map<String, String> toJson() => {
    'family': family.name,
    'address': address,
    'message': message,
    'signature': signature,
    'publicKey': ?publicKey,
    'nonce': ?nonce,
    'recipient': ?recipient,
  };

  factory SignedMessage.fromJson(Map<String, dynamic> json) => SignedMessage(
    family: ChainFamily.values.byName(json['family'] as String),
    address: json['address'] as String,
    message: json['message'] as String,
    signature: json['signature'] as String,
    publicKey: json['publicKey'] as String?,
    nonce: json['nonce'] as String?,
    recipient: json['recipient'] as String?,
  );
}
