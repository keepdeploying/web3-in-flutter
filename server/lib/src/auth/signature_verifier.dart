import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../chain_family.dart';
import '../signing/message_formats.dart';
import '../signing/signed_message.dart';
import 'chain_lookup.dart';

/// The outcome of checking one signed message.
class Verification {
  const Verification.valid(this.how) : valid = true, reason = null;
  const Verification.invalid(this.reason, {this.how = ''}) : valid = false;

  final bool valid;

  /// Why it failed, in words a user can act on.
  final String? reason;

  /// How the check was done, for the app's "What's happening" card.
  final String how;
}

/// Checks that a [SignedMessage] was really signed by the account it names.
///
/// This is the heart of "Sign in with a wallet": the server never sees a
/// password, only a signature, and it proves who you are because only the
/// private key could have made it. Each chain wraps and hashes the message
/// its own way (see `message_formats.dart`) and links keys to addresses its
/// own way, so each needs its own check.
class SignatureVerifier {
  SignatureVerifier({this.lookup = const OfflineChainLookup(), this.nearRecipient = 'flutter-counter.app'});

  final ChainLookup lookup;

  /// NEP-413's recipient this server accepts: a signature made for another
  /// app is refused.
  final String nearRecipient;

  /// [evmChainId] is only needed for smart contract wallets, whose check
  /// runs on a specific chain.
  Future<Verification> verify(SignedMessage signed, {String? evmChainId}) async {
    if (signed.message.isEmpty) return const Verification.invalid('The message is empty.');
    try {
      return switch (signed.family) {
        ChainFamily.evm => await _evm(signed, evmChainId),
        ChainFamily.solana => _solana(signed),
        ChainFamily.sui => await _sui(signed),
        ChainFamily.cosmos => _cosmos(signed),
        ChainFamily.near => await _near(signed),
      };
    } on Object catch (e) {
      // Malformed input (bad base64, wrong lengths, points off the curve...)
      // is just an invalid signature, never a server error.
      return Verification.invalid('The signature could not be read: $e');
    }
  }

  Future<Verification> _evm(SignedMessage signed, String? chainId) async {
    final hash = Eip191.hash(signed.message);
    final signature = BytesUtils.fromHexString(signed.signature);
    if (signature.length != 65) return const Verification.invalid('An EVM signature is 65 bytes (r, s, v).');

    // ecrecover: from the hash and (r, s, v), compute the only public key
    // that could have signed, then its address.
    final key = ETHVerifier.getPublicKey(hash, signature, hashMessage: false);
    final recovered = key == null ? null : EthAddrEncoder().encodeKey(key.toBytes());
    if (recovered != null && recovered.toLowerCase() == signed.address.toLowerCase()) {
      return Verification.valid('Recovered $recovered from the signature (ecrecover). It matches the account.');
    }

    // Not the account's own key: it may be a smart contract wallet.
    if (chainId != null &&
        await lookup.erc1271IsValid(chainId: chainId, address: signed.address, hash: hash, signature: signature)) {
      return const Verification.valid(
        'The account is a contract wallet, and its isValidSignature accepted it (ERC-1271).',
      );
    }
    return Verification.invalid('The signature belongs to ${recovered ?? 'no valid key'}, not ${signed.address}.');
  }

  Verification _solana(SignedMessage signed) {
    // A Solana address is the ed25519 public key itself, in base58.
    final publicKey = Base58Decoder.decode(signed.address);
    final signature = Base58Decoder.decode(signed.signature);
    if (publicKey.length != 32 || signature.length != 64) {
      return const Verification.invalid('Expected a 32-byte key and a 64-byte signature.');
    }
    final ok = Ed25519Verifier.fromKeyBytes(publicKey).verify(SolanaMessage.bytes(signed.message), signature);
    return ok
        ? const Verification.valid('The address is the public key, and the ed25519 signature matches the message.')
        : const Verification.invalid('The ed25519 signature does not match this message and address.');
  }

  Future<Verification> _sui(SignedMessage signed) async {
    final flag = base64Decode(signed.signature).first;
    if (flag == SuiPersonalMessage.zkLoginFlag) {
      // zkLogin proofs need a full node, so ask one.
      final ok = await lookup.suiSignatureIsValid(
        message: signed.message,
        signature: signed.signature,
        address: signed.address,
      );
      return ok
          ? const Verification.valid('A Sui full node checked the zkLogin proof and accepted it.')
          : const Verification.invalid('The Sui network did not accept this zkLogin signature.');
    }

    final parts = SuiPersonalMessage.parse(signed.signature);
    // The key travels inside the signature, so first check it is really
    // this address's key: the address is a hash of the flag and the key.
    final address = SuiPersonalMessage.address(parts.flag, parts.publicKey);
    if (address != signed.address.toLowerCase()) {
      return Verification.invalid('The key in the signature belongs to $address, not ${signed.address}.');
    }
    final digest = SuiPersonalMessage.digest(signed.message);
    final ok = parts.flag == SuiPersonalMessage.ed25519Flag
        ? Ed25519Verifier.fromKeyBytes(parts.publicKey).verify(digest, parts.signature)
        // secp256k1 keys sign sha256 of the digest.
        : Secp256k1Verifier.fromKeyBytes(parts.publicKey).verify(digest, parts.signature, hashMessage: true);
    return ok
        ? Verification.valid(
            'The key in the signature hashes to the address, and the '
            '${parts.flag == 0 ? 'ed25519' : 'secp256k1'} signature matches the personal message digest.',
          )
        : const Verification.invalid('The signature does not match this personal message.');
  }

  Verification _cosmos(SignedMessage signed) {
    final publicKey = base64Decode(signed.publicKey ?? '');
    final signature = base64Decode(signed.signature);
    if (publicKey.length != 33 || signature.length != 64) {
      return const Verification.invalid('Expected a 33-byte public key and a 64-byte signature.');
    }
    // A Cosmos address is only a hash of the key (ripemd160 of sha256), so
    // the key travels with the signature. Check it matches the address.
    // The human-readable prefix ("osmo") is everything before the last "1".
    final hrp = signed.address.substring(0, signed.address.lastIndexOf('1'));
    final address = AtomAddrEncoder().encodeKey(publicKey, hrp: hrp);
    if (address != signed.address) {
      return Verification.invalid('The public key belongs to $address, not ${signed.address}.');
    }
    // Cosmos SDK chains accept only low-S signatures (see the signer).
    final s = BigintUtils.fromBytes(signature.sublist(32));
    if (s > Curves.generatorSecp256k1.order! >> 1) {
      return const Verification.invalid('High-S signatures are not accepted on Cosmos chains.');
    }
    final digest = Adr36.digest(signer: signed.address, message: signed.message);
    final ok = Secp256k1Verifier.fromKeyBytes(publicKey).verify(digest, signature);
    return ok
        ? const Verification.valid(
            'The public key hashes to the address, and the secp256k1 signature matches the ADR-36 sign doc.',
          )
        : const Verification.invalid('The signature does not match the ADR-36 sign doc for this message.');
  }

  Future<Verification> _near(SignedMessage signed) async {
    final publicKeyText = signed.publicKey ?? '';
    if (!publicKeyText.startsWith('ed25519:')) return const Verification.invalid('Expected an ed25519 public key.');
    if (signed.recipient != nearRecipient) {
      return Verification.invalid(
        'The message was signed for "${signed.recipient}", not for this app ("$nearRecipient").',
      );
    }
    final publicKey = Base58Decoder.decode(publicKeyText.substring(8));
    final hash = Nep413.hash(
      message: signed.message,
      nonce: base64Decode(signed.nonce ?? ''),
      recipient: signed.recipient!,
    );
    if (!Ed25519Verifier.fromKeyBytes(publicKey).verify(hash, base64Decode(signed.signature))) {
      return const Verification.invalid('The ed25519 signature does not match the NEP-413 payload.');
    }

    // The signature is valid for this key. Is the key the account's?
    // An implicit account's ID is its key in hex, so no lookup is needed.
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(signed.address)) {
      return BytesUtils.toHexString(publicKey) == signed.address
          ? const Verification.valid('The NEP-413 signature matches, and the implicit account ID is this key in hex.')
          : const Verification.invalid('This key is not the key of that implicit account.');
    }
    return await lookup.nearHasFullAccessKey(accountId: signed.address, publicKey: publicKeyText)
        ? Verification.valid(
            'The NEP-413 signature matches, and NEAR says the key is a full-access key of ${signed.address}.',
          )
        : Verification.invalid('NEAR says this key is not a full-access key of ${signed.address}.');
  }
}
