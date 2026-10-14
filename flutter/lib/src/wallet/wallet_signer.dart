import 'package:flutter_counter_server/flutter_counter_server.dart';

export 'package:flutter_counter_server/flutter_counter_server.dart' show ChainFamily, SignedMessage;

/// Anything that can sign for one account on one chain family.
///
/// The in-app wallet, an installed wallet reached by deep link or browser
/// extension, and a WalletConnect session through Reown all end up behind
/// this interface. Sign-in and writes don't care which one it is.
abstract class WalletSigner {
  ChainFamily get family;

  /// The account address, in the chain's usual format.
  String get address;

  /// Where the keys live, for the UI: "In-app wallet", "Phantom", ...
  String get name;

  /// Signs [message] the way the chain's wallets do (EIP-191, Sui personal
  /// message, ADR-36, NEP-413...). See `message_formats.dart`.
  ///
  /// [nearNonce] is NEAR only: NEP-413 signs a 32-byte nonce next to the
  /// message. At sign-in level 3 the server chooses it; otherwise the signer
  /// makes a random one.
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce});
}
