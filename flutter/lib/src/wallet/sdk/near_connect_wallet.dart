import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:near_wallet_connect/near_wallet_connect.dart';

import '../../chains/networks.dart';
import '../in_app_signer.dart';
import '../installed/installed_wallet.dart';
import '../wallet_signer.dart';

/// NEAR wallets through `near_wallet_connect`, which hides each wallet's
/// own protocol behind one controller.
///
/// NEAR has no standard for apps to reach wallets, so this is the only way
/// out besides the in-app wallet. The package also knows HOT (mainnet
/// only), Bitte and HERE (no NEP-413 messages, so no sign-in) and
/// MyNearWallet (shutting down on October 31, 2026). Intear is the one that
/// does both things this app needs on testnet: NEP-413 messages for
/// sign-in, and transactions for writes.
class NearConnectWallet extends InstalledWallet {
  NearConnectWallet(this.option);

  final NearWalletOption option;

  /// Made when first needed: it opens storage and an RPC client.
  NearWalletController get controller => sharedController();

  /// One controller for all NEAR wallet options, made on first use.
  static NearWalletController? _shared;
  static NearWalletController sharedController() => _shared ??= NearWalletController(
    network: MyNearWalletNetwork.testnet,
    contractId: AccountId(Networks.nearTestnet.counter),
    methodNames: const ['increment', 'decrement', 'reset'],
    // Wallets answer on fluttercounter://callback (or this page on the web).
    callbackScheme: 'fluttercounter',
  );

  static List<NearConnectWallet> all() => [NearConnectWallet(NearWalletOption.intear)];

  static bool _initialized = false;

  @override
  String get id => 'near:${option.name}';

  @override
  String get name => option.label;

  @override
  String? get icon => null;

  @override
  String get via => 'near_wallet_connect';

  @override
  Set<ChainFamily> get families => const {ChainFamily.near};

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) async {
    if (!_initialized) {
      await controller.init();
      _initialized = true;
    }
    await controller.connect(wallet: option);
    final account = controller.account;
    if (account == null) {
      final error = controller.lastException;
      throw WalletException(
        error?.message ?? '$name did not connect.',
        declined: error?.code == NearErrorCode.userRejected,
      );
    }

    void changed() {
      if (controller.account?.accountId != account.accountId) {
        controller.removeListener(changed);
        onLost();
      }
    }

    controller.addListener(changed);
    return NearConnectSigner(this, account.accountId.value);
  }
}

class NearConnectSigner extends InstalledSigner implements NearFunctionCaller {
  NearConnectSigner(this.wallet, this.address);

  @override
  final NearConnectWallet wallet;

  @override
  final String address;

  NearWalletController get _controller => wallet.controller;

  @override
  ChainFamily get family => ChainFamily.near;

  Future<T> _guard<T>(Future<T> Function() work) async {
    try {
      return await work();
    } on NearSdkException catch (e) {
      throw WalletException(
        e.code == NearErrorCode.userRejected ? 'You declined the request in ${wallet.name}.' : e.message,
        code: e.code.name,
        declined: e.code == NearErrorCode.userRejected,
      );
    }
  }

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) => _guard(() async {
    // NEP-413: the same message, nonce and recipient the in-app wallet signs.
    final nonce = nearNonce ?? QuickCrypto.generateRandom(32);
    const recipient = InAppSigner.defaultRecipient;
    final signed = await _controller.signMessage(Nep413Payload(message: message, nonce: nonce, recipient: recipient));
    return SignedMessage(
      family: family,
      address: signed.accountId.value,
      message: message,
      signature: signed.signature,
      publicKey: signed.publicKey.toString(),
      nonce: base64Encode(nonce),
      recipient: recipient,
    );
  });

  @override
  Future<String> callNearFunction(Network network, {required String contract, required String method}) =>
      _guard(() async {
        final outcomes = await _controller.sendTransactions([
          {
            'receiverId': contract,
            'actions': [
              {
                'type': 'FunctionCall',
                'params': {'methodName': method, 'args': <String, Object>{}, 'gas': '30000000000000', 'deposit': '0'},
              },
            ],
          },
        ]);
        // An execution outcome, as the RPC's send_tx returns it.
        final outcome = outcomes.first;
        final transaction = outcome is Map ? outcome['transaction'] : null;
        final hash = transaction is Map ? transaction['hash'] : null;
        if (hash == null) throw WalletException('${wallet.name} sent the transaction but returned no hash.');
        return '$hash';
      });

  @override
  Future<void> disconnect() => _controller.disconnect();
}
