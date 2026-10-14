import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../../../chains/networks.dart';
import '../../wallet_signer.dart';
import '../installed_wallet.dart';
import 'js.dart';

/// A wallet as the Wallet Standard describes it.
extension type WalletObject._(JSObject _) implements JSObject {
  external String get name;
  external String get icon;
  external JSArray<JSString> get chains;

  /// Feature name (`standard:connect`, `solana:signMessage`...) to an
  /// object with that feature's methods.
  external JSObject get features;
  external JSArray<WalletAccount> get accounts;
}

/// One account a wallet shared with the page.
extension type WalletAccount._(JSObject _) implements JSObject {
  external String get address;
  external JSArray<JSString> get chains;
}

/// The Wallet Standard: how a page finds Solana and Sui wallet extensions
/// (and wallets of other chains that adopt it).
///
/// Wallets and the page find each other with two window events, so neither
/// has to load first:
/// - each wallet dispatches `wallet-standard:register-wallet` with a
///   callback, and the page calls it with its `register` function;
/// - the page dispatches `wallet-standard:app-ready` with `register`, for
///   wallets that loaded earlier.
///
/// A wallet is an object with a name, an icon, the chains it supports
/// (`solana:devnet`, `sui:testnet`...) and features: `standard:connect`,
/// `solana:signTransaction`, `sui:signPersonalMessage`, and so on.
abstract final class WalletStandard {
  static void listen(void Function(InstalledWallet wallet) onWallet) {
    void add(JSAny? wallet) {
      if (wallet == null) return;
      final standard = StandardWallet(wallet as WalletObject);
      if (standard.families.isNotEmpty) onWallet(standard);
    }

    // Wallets register one at a time. (A JavaScript function made from a
    // Dart one must be called with the number of arguments it declares.)
    JSFunction register(JSAny? wallet) {
      add(wallet);
      // The standard expects a function that unregisters it.
      return (() {}).toJS;
    }

    final api = jsObject({'register': register.toJS});
    web.window.addEventListener(
      'wallet-standard:register-wallet',
      (web.Event event) {
        ((event as web.CustomEvent).detail as JSFunction).callAsFunction(null, api);
      }.toJS,
    );
    web.window.dispatchEvent(web.CustomEvent('wallet-standard:app-ready', web.CustomEventInit(detail: api)));
  }
}

class StandardWallet extends InstalledWallet {
  StandardWallet(this._wallet);

  final WalletObject _wallet;

  @override
  String get id => 'standard:$name';

  @override
  String get name => _wallet.name;

  @override
  String get icon => _wallet.icon;

  @override
  String get via => 'Wallet Standard';

  @override
  Set<ChainFamily> get families => {
    for (final chain in _wallet.chains.toDart.map((c) => c.toDart))
      if (chain.startsWith('solana:')) ChainFamily.solana else if (chain.startsWith('sui:')) ChainFamily.sui,
  };

  /// The feature's object, or null if the wallet doesn't have it.
  JSObject? feature(String name) => _wallet.features.getProperty<JSObject?>(name.toJS);

  /// Calls [method] of [featureName] with one [input] object.
  Future<JSAny?> call(String featureName, String method, JSObject? input) {
    final target = feature(featureName);
    if (target == null) throw WalletException("$name doesn't support $featureName.");
    return walletCall(name, () => target.callMethod<JSPromise<JSAny?>>(method.toJS, input));
  }

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) async {
    final prefix = switch (network.family) {
      ChainFamily.solana => 'solana:',
      ChainFamily.sui => 'sui:',
      _ => throw WalletException("$name doesn't support ${network.family.label}."),
    };
    // The wallet asks the user to share their accounts with this site.
    final result = await call('standard:connect', 'connect', null) as JSObject;
    final accounts = result.getProperty<JSArray<WalletAccount>>('accounts'.toJS).toDart;
    final account = accounts.where((a) => a.chains.toDart.any((c) => c.toDart.startsWith(prefix))).firstOrNull;
    if (account == null) throw WalletException('$name shared no ${network.family.label} account.');

    // Tell the app when the user switches account or disconnects.
    JSFunction? off;
    if (feature('standard:events') case final events?) {
      void onChange(JSObject properties) {
        final now = properties.getProperty<JSArray<WalletAccount>?>('accounts'.toJS);
        if (now != null && !now.toDart.any((a) => a.address == account.address)) onLost();
      }

      off = events.callMethod<JSFunction>('on'.toJS, 'change'.toJS, onChange.toJS);
    }
    return network.family == ChainFamily.solana
        ? StandardSolanaSigner(this, account, off)
        : StandardSuiSigner(this, account, off);
  }
}

/// What both kinds of Wallet Standard signer share.
abstract class _StandardSigner extends InstalledSigner {
  _StandardSigner(this.wallet, this._account, this._off);

  @override
  final StandardWallet wallet;

  /// The wallet's own account object: wallets check that requests carry it.
  final WalletAccount _account;
  final JSFunction? _off;

  @override
  String get address => _account.address;

  /// `solana:devnet`, `sui:testnet`...
  String chainOf(Network network);

  @override
  Future<void> disconnect() async {
    _off?.callAsFunction();
    if (wallet.feature('standard:disconnect') != null) {
      await wallet.call('standard:disconnect', 'disconnect', null).catchError((_) => null);
    }
  }
}

class StandardSolanaSigner extends _StandardSigner implements SolanaTransactionSigner {
  StandardSolanaSigner(super.wallet, super.account, super.off);

  @override
  ChainFamily get family => ChainFamily.solana;

  @override
  String chainOf(Network network) => 'solana:${network.chainId}';

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    // Solana signs the message bytes as they are, with ed25519.
    final results = await wallet.call(
      'solana:signMessage',
      'signMessage',
      jsObject({'account': _account, 'message': Uint8List.fromList(utf8.encode(message)).toJS}),
    );
    final output = (results as JSArray<JSObject>).toDart.first;
    final signature = output.getProperty<JSUint8Array>('signature'.toJS).toDart;
    return SignedMessage(
      family: family,
      address: address,
      message: message,
      signature: Base58Encoder.encode(signature),
    );
  }

  @override
  Future<List<int>> signSolanaTransaction(List<int> transaction, Network network) async {
    final results = await wallet.call(
      'solana:signTransaction',
      'signTransaction',
      jsObject({
        'account': _account,
        'transaction': Uint8List.fromList(transaction).toJS,
        'chain': chainOf(network).toJS,
      }),
    );
    final output = (results as JSArray<JSObject>).toDart.first;
    return output.getProperty<JSUint8Array>('signedTransaction'.toJS).toDart;
  }
}

class StandardSuiSigner extends _StandardSigner implements SuiTransactionSigner {
  StandardSuiSigner(super.wallet, super.account, super.off);

  @override
  ChainFamily get family => ChainFamily.sui;

  @override
  String chainOf(Network network) => 'sui:${network.chainId}';

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    // The wallet adds the PersonalMessage intent and signs the digest, as
    // SuiPersonalMessage does in the in-app wallet. The signature comes back
    // serialized: flag, signature, public key.
    final output = await wallet.call(
      'sui:signPersonalMessage',
      'signPersonalMessage',
      jsObject({'account': _account, 'message': Uint8List.fromList(utf8.encode(message)).toJS}),
    ) as JSObject;
    return SignedMessage(
      family: family,
      address: address,
      message: message,
      signature: output.getProperty<JSString>('signature'.toJS).toDart,
    );
  }

  @override
  Future<({String bytes, String signature})> signSuiTransaction(List<int> transactionData, Network network) async {
    // Wallets take a transaction object with a toJSON method, which they
    // pass to the Sui SDK's Transaction.from. That also accepts finished
    // BCS bytes in base64, so the wallet signs exactly what the app built.
    final transaction = jsObject({'toJSON': (() => Future.value(base64Encode(transactionData).toJS).toJS).toJS});
    final output = await wallet.call(
      'sui:signTransaction',
      'signTransaction',
      jsObject({'account': _account, 'transaction': transaction, 'chain': chainOf(network).toJS}),
    ) as JSObject;
    return (
      bytes: output.getProperty<JSString>('bytes'.toJS).toDart,
      signature: output.getProperty<JSString>('signature'.toJS).toDart,
    );
  }
}
