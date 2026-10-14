import 'package:flutter_counter_server/flutter_counter_server.dart';

import '../chains/networks.dart';

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

// What a wallet can do with a transaction differs by chain. On Solana, Sui
// and Cosmos, wallets sign a transaction the app built, and the app sends
// it. On EVM chains and NEAR, wallets want to build and send it
// themselves: the app only says which contract method to call.
//
// A signer implements the interfaces its wallet supports, and each
// CounterWriter checks for the one it needs.

/// Signs a Solana transaction the app built.
abstract interface class SolanaTransactionSigner implements WalletSigner {
  /// Signs [transaction] (zeroed signature slots, then the message) and
  /// returns the signed transaction, ready to send. Send what comes back:
  /// some wallets add instructions, such as a priority fee, before signing.
  Future<List<int>> signSolanaTransaction(List<int> transaction, Network network);
}

/// Signs Sui `TransactionData` the app built, in BCS.
abstract interface class SuiTransactionSigner implements WalletSigner {
  /// Returns the transaction bytes the wallet signed and the serialized
  /// signature (flag, signature, public key), both in base64.
  Future<({String bytes, String signature})> signSuiTransaction(List<int> transactionData, Network network);
}

/// Signs a Cosmos transaction in SIGN_MODE_DIRECT.
abstract interface class CosmosDirectSigner implements WalletSigner {
  /// The compressed secp256k1 public key, which goes in the AuthInfo.
  List<int> get publicKey;

  /// Signs the SignDoc made of [body], [authInfo], the chain ID and
  /// [accountNumber]. Returns what the wallet signed (it could change the
  /// fee) and the 64-byte signature.
  Future<({List<int> body, List<int> authInfo, List<int> signature})> signDirect({
    required List<int> body,
    required List<int> authInfo,
    required Network network,
    required int accountNumber,
  });
}

/// An EVM wallet that builds, signs and sends a transaction itself.
abstract interface class EvmTransactionSender implements WalletSigner {
  /// Asks the wallet to call [to] with [data] on [network], switching the
  /// wallet to that network first. The wallet picks the nonce, gas and
  /// fees, shows the user what they approve, and returns the hash.
  Future<String> sendEvmTransaction(Network network, {required String to, required String data});
}

/// A NEAR wallet that builds, signs and sends a function call itself.
abstract interface class NearFunctionCaller implements WalletSigner {
  /// Calls [method] on [contract] with no arguments and no deposit, and
  /// returns the transaction hash once it has run.
  Future<String> callNearFunction(Network network, {required String contract, required String method});
}
