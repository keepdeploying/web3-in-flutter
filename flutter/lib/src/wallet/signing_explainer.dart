import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';

import '../ui/widgets/whats_happening.dart';

/// Turns one message signature into "What's happening" steps: the standard,
/// the exact bytes that were hashed, the hash, and the signature.
List<HappeningStep> explainSigning(SignedMessage signed, {String? path}) {
  final message = signed.message;
  final key = path == null ? 'your private key' : 'the key at $path';
  HappeningStep done(String title, String detail, [String? code]) =>
      HappeningStep(title: title, detail: detail, code: code, status: StepStatus.done);

  final steps = switch (signed.family) {
    ChainFamily.evm => [
      done(
        'Wrap it (EIP-191)',
        'Prefix "\\x19Ethereum Signed Message:\\n" and the byte length, so it can never be a transaction.',
        '\\x19Ethereum Signed Message:\\n${utf8.encode(message).length}$message',
      ),
      done('Hash it with keccak256', 'The key signs this 32-byte hash.', _hex(Eip191.hash(message))),
      done(
        'Sign with secp256k1',
        'Signed with $key. The result is r, s and v: v lets anyone recover the public key, '
            'and from it the address, so the address is all a verifier needs.',
        signed.signature,
      ),
    ],
    ChainFamily.solana => [
      done(
        'Use the bytes as they are',
        'Solana wallets sign the UTF-8 bytes directly. Instead of a prefix, they refuse to sign '
            'anything that parses as a transaction.',
        _hex(SolanaMessage.bytes(message)),
      ),
      done(
        'Sign with ed25519',
        'Signed with $key. A Solana address is the public key itself, so verifiers need nothing else.',
        signed.signature,
      ),
    ],
    ChainFamily.sui => [
      done(
        'Wrap it in a personal message intent',
        'Intent bytes [3, 0, 0] (personal message, version 0, Sui), then the message as BCS vector<u8>.',
        _hex([...SuiPersonalMessage.intent, ...uleb128(utf8.encode(message).length), ...utf8.encode(message)]),
      ),
      done('Hash it with blake2b-256', 'The key signs this 32-byte digest.', _hex(SuiPersonalMessage.digest(message))),
      done(
        'Sign with ed25519 and serialize',
        'Signed with $key. Sui packs a scheme flag (0 for ed25519), the signature and the public key '
            'into one base64 string.',
        signed.signature,
      ),
    ],
    ChainFamily.cosmos => [
      done(
        'Put it in an ADR-36 sign doc',
        'A fake Amino transaction: empty chain ID, zero fees, and the message base64-encoded inside '
            'a sign/MsgSignData. No chain would ever accept it.',
        Adr36.signDoc(signer: signed.address, message: message),
      ),
      done(
        'Hash it with sha256',
        'The key signs this 32-byte hash.',
        _hex(Adr36.digest(signer: signed.address, message: message)),
      ),
      done(
        'Sign with secp256k1 (low-S)',
        'Signed with $key. A Cosmos address is only a hash of the public key, so the public key '
            'travels with the signature.',
        'signature: ${signed.signature}\npub_key: ${signed.publicKey}',
      ),
    ],
    ChainFamily.near => [
      done(
        'Build the NEP-413 payload',
        'Borsh-encode the message, a random 32-byte nonce, the recipient (who the message is for) and an '
            'empty callback URL. Prefix the tag 2^31 + 413, which no transaction can start with.',
        'message: $message\nnonce: ${signed.nonce}\nrecipient: ${signed.recipient}',
      ),
      done(
        'Hash it with sha256',
        'The key signs this 32-byte hash.',
        _hex(Nep413.hash(message: message, nonce: base64Decode(signed.nonce!), recipient: signed.recipient!)),
      ),
      done(
        'Sign with ed25519',
        'Signed with $key. A NEAR account can have many keys, so the public key travels with the '
            'signature, and the backend checks that it belongs to the account.',
        'signature: ${signed.signature}\npublicKey: ${signed.publicKey}',
      ),
    ],
  };
  return steps;
}

String _hex(List<int> bytes) => BytesUtils.toHexString(bytes, prefix: '0x');
