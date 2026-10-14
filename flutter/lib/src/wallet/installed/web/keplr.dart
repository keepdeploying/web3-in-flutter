import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../../../chains/networks.dart';
import '../../wallet_signer.dart';
import '../installed_wallet.dart';
import 'js.dart';

/// Keplr's API, which Leap copies: one object on `window` with a method per
/// request.
extension type KeplrApi._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> enable(String chainId);
  external JSPromise<JSAny?> experimentalSuggestChain(JSObject chainInfo);
  external JSPromise<KeplrKey> getKey(String chainId);
  external JSPromise<JSObject> signArbitrary(String chainId, String signer, String data);
  external JSPromise<JSObject> signDirect(String chainId, String signer, JSObject signDoc, JSObject options);
}

extension type KeplrKey._(JSObject _) implements JSObject {
  external String get bech32Address;
  external JSUint8Array get pubKey;
}

/// Cosmos wallets have no discovery standard. Keplr puts itself at
/// `window.keplr`, Leap at `window.leap`, so the page looks for both. They
/// may load after the page, so it looks again a little later.
abstract final class KeplrWallets {
  static const known = {'keplr': 'Keplr', 'leap': 'Leap'};

  static void listen(void Function(InstalledWallet wallet) onWallet) {
    void look() {
      for (final MapEntry(key: property, value: name) in known.entries) {
        final api = web.window.getProperty<JSObject?>(property.toJS);
        if (api != null) onWallet(KeplrWallet(api as KeplrApi, property: property, name: name));
      }
    }

    look();
    web.window.addEventListener('load', ((web.Event _) => look()).toJS);
    for (final seconds in [1, 3]) {
      Timer(Duration(seconds: seconds), look);
    }
  }
}

class KeplrWallet extends InstalledWallet {
  KeplrWallet(this.api, {required this.property, required this.name});

  final KeplrApi api;

  /// Where it lives on `window`: `keplr` or `leap`.
  final String property;

  @override
  String get id => 'window:$property';

  @override
  final String name;

  @override
  String? get icon => null;

  @override
  String get via => 'window.$property';

  @override
  Set<ChainFamily> get families => const {ChainFamily.cosmos};

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) async {
    try {
      await walletCall(name, () => api.enable(network.chainId));
    } on WalletException catch (e) {
      if (e.declined) rethrow;
      // The wallet doesn't know this chain yet: describe it, then retry.
      // The user sees the details and approves adding it.
      await walletCall(name, () => api.experimentalSuggestChain(_chainInfo(network)));
      await walletCall(name, () => api.enable(network.chainId));
    }
    final key = await walletCall(name, () => api.getKey(network.chainId));
    final signer = KeplrSigner(this, key.bech32Address, key.pubKey.toDart, network.chainId);

    // Keplr fires this when the user switches account.
    late final JSFunction listener;
    listener = ((web.Event _) {
      web.window.removeEventListener('${property}_keystorechange', listener);
      onLost();
    }).toJS;
    web.window.addEventListener('${property}_keystorechange', listener);
    return signer;
  }

  /// What Keplr needs to add Osmosis Testnet: endpoints, address prefix,
  /// key derivation (coin type 118) and the fee token.
  static JSObject _chainInfo(Network network) {
    const prefix = 'osmo';
    final currency = {'coinDenom': network.symbol, 'coinMinimalDenom': 'uosmo', 'coinDecimals': network.decimals};
    return {
          'chainId': network.chainId,
          'chainName': network.name,
          'rpc': 'https://rpc.osmotest5.osmosis.zone',
          'rest': network.rpcUrls.first,
          'bip44': {'coinType': 118},
          'bech32Config': {
            'bech32PrefixAccAddr': prefix,
            'bech32PrefixAccPub': '${prefix}pub',
            'bech32PrefixValAddr': '${prefix}valoper',
            'bech32PrefixValPub': '${prefix}valoperpub',
            'bech32PrefixConsAddr': '${prefix}valcons',
            'bech32PrefixConsPub': '${prefix}valconspub',
          },
          'currencies': [currency],
          'feeCurrencies': [
            {
              ...currency,
              'gasPriceStep': {'low': 0.0025, 'average': 0.025, 'high': 0.04},
            },
          ],
          'stakeCurrency': currency,
          'features': ['cosmwasm'],
        }.jsify()
        as JSObject;
  }
}

class KeplrSigner extends InstalledSigner implements CosmosDirectSigner {
  KeplrSigner(this.wallet, this.address, this.publicKey, this.chainId);

  @override
  final KeplrWallet wallet;

  @override
  final String address;

  @override
  final List<int> publicKey;

  /// The chain it was enabled for. Keplr needs one for every request,
  /// even ADR-36 messages, which are signed with chain ID "".
  final String chainId;

  @override
  ChainFamily get family => ChainFamily.cosmos;

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    // ADR-36: the wallet wraps the text in an amino sign doc with a
    // MsgSignData, chain ID "" and zero fee, then signs its sha256.
    final result = await walletCall(wallet.name, () => wallet.api.signArbitrary(chainId, address, message));
    final publicKey = result.getProperty<JSObject>('pub_key'.toJS).getProperty<JSString>('value'.toJS).toDart;
    return SignedMessage(
      family: family,
      address: address,
      message: message,
      signature: result.getProperty<JSString>('signature'.toJS).toDart,
      publicKey: publicKey,
    );
  }

  @override
  Future<({List<int> body, List<int> authInfo, List<int> signature})> signDirect({
    required List<int> body,
    required List<int> authInfo,
    required Network network,
    required int accountNumber,
  }) async {
    final signDoc = jsObject({
      'bodyBytes': Uint8List.fromList(body).toJS,
      'authInfoBytes': Uint8List.fromList(authInfo).toJS,
      'chainId': network.chainId.toJS,
      // Keplr only calls toString() on it, so a string does.
      'accountNumber': '$accountNumber'.toJS,
    });
    // Keep the app's fee, which comes from a simulation and the current
    // base fee, instead of the wallet's.
    final options = jsObject({'preferNoSetFee': true.toJS});
    final result = await walletCall(
      wallet.name,
      () => wallet.api.signDirect(network.chainId, address, signDoc, options),
    );
    final signed = result.getProperty<JSObject>('signed'.toJS);
    final signature = result.getProperty<JSObject>('signature'.toJS).getProperty<JSString>('signature'.toJS).toDart;
    return (
      body: signed.getProperty<JSUint8Array>('bodyBytes'.toJS).toDart,
      authInfo: signed.getProperty<JSUint8Array>('authInfoBytes'.toJS).toDart,
      signature: base64Decode(signature),
    );
  }
}
