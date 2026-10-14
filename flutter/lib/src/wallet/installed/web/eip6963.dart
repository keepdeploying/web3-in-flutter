import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui' show VoidCallback;

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:web/web.dart' as web;

import '../../../chains/evm/evm_address.dart';
import '../../../chains/networks.dart';
import '../../wallet_signer.dart';
import '../installed_wallet.dart';
import 'js.dart';

/// An EVM wallet's provider object, as EIP-1193 defines it: one `request`
/// method for every JSON-RPC call, and events.
extension type Eip1193Provider._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(JSObject arguments);
  external void on(String event, JSFunction listener);
  external void removeListener(String event, JSFunction listener);
}

extension type _ProviderDetail._(JSObject _) implements JSObject {
  external _ProviderInfo get info;
  external Eip1193Provider get provider;
}

extension type _ProviderInfo._(JSObject _) implements JSObject {
  external String get uuid;
  external String get name;
  external String get icon;
  external String get rdns;
}

/// EIP-6963: how a page finds every EVM wallet extension in the browser.
///
/// Before it, each extension wrote itself into `window.ethereum`, and the
/// last one to load won. Now the page sends `eip6963:requestProvider`, and
/// each wallet answers with an `eip6963:announceProvider` event carrying its
/// name, icon, reverse-DNS ID and provider. Wallets also announce on their
/// own when they load, so the page listens first, then asks.
abstract final class Eip6963 {
  static void listen(void Function(InstalledWallet wallet) onWallet) {
    web.window.addEventListener(
      'eip6963:announceProvider',
      (web.Event event) {
        final detail = (event as web.CustomEvent).detail as _ProviderDetail;
        final info = detail.info;
        onWallet(Eip6963Wallet(detail.provider, rdns: info.rdns, name: info.name, icon: info.icon));
      }.toJS,
    );
    web.window.dispatchEvent(web.Event('eip6963:requestProvider'));
  }
}

class Eip6963Wallet extends InstalledWallet {
  Eip6963Wallet(this.provider, {required this.rdns, required this.name, required this.icon});

  final Eip1193Provider provider;

  /// The wallet's reverse-DNS name, like `io.metamask`.
  final String rdns;

  @override
  String get id => 'eip6963:$rdns';

  @override
  final String name;

  @override
  final String icon;

  @override
  String get via => 'EIP-6963';

  @override
  Set<ChainFamily> get families => const {ChainFamily.evm};

  /// Sends one JSON-RPC request to the wallet.
  Future<Object?> request(String method, [List<Object?>? params]) async {
    final arguments = {'method': method, 'params': ?params}.jsify() as JSObject;
    final result = await walletCall(name, () => provider.request(arguments));
    return result.dartify();
  }

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) async {
    // The wallet asks the user which accounts to share with this site.
    final accounts = (await request('eth_requestAccounts') as List).cast<String>();
    if (accounts.isEmpty) throw WalletException('$name shared no account.');
    return Eip6963Signer(this, toChecksumAddress(accounts.first), onLost);
  }
}

/// Signs with an account in an EIP-6963 wallet.
class Eip6963Signer extends InstalledSigner implements EvmTransactionSender {
  Eip6963Signer(this.wallet, this.address, VoidCallback onLost) {
    // Switching accounts in the wallet, or locking it, changes the list.
    _onAccountsChanged = (JSArray<JSString> accounts) {
      final list = accounts.toDart.map((a) => a.toDart.toLowerCase());
      if (!list.contains(address.toLowerCase())) onLost();
    }.toJS;
    wallet.provider.on('accountsChanged', _onAccountsChanged);
  }

  @override
  final Eip6963Wallet wallet;

  @override
  final String address;

  late final JSFunction _onAccountsChanged;

  @override
  ChainFamily get family => ChainFamily.evm;

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    // personal_sign takes the message as hex. The wallet shows it as text,
    // adds the EIP-191 prefix, and signs the hash: exactly what Eip191.hash
    // does in the in-app wallet.
    final hex = BytesUtils.toHexString(utf8.encode(message), prefix: '0x');
    final signature = await wallet.request('personal_sign', [hex, address]) as String;
    return SignedMessage(family: family, address: address, message: message, signature: signature);
  }

  @override
  Future<String> sendEvmTransaction(Network network, {required String to, required String data}) async {
    await _switchTo(network);
    // Only from, to and data: the wallet fills in the nonce, gas and fees.
    return await wallet.request('eth_sendTransaction', [
          {'from': address, 'to': to, 'data': data},
        ])
        as String;
  }

  /// Wallets send transactions on the chain they are set to, so switch it
  /// first, and add the chain if the wallet doesn't know it yet.
  Future<void> _switchTo(Network network) async {
    final chainId = '0x${int.parse(network.chainId).toRadixString(16)}';
    final current = await wallet.request('eth_chainId') as String;
    if (int.parse(current.substring(2), radix: 16) == int.parse(network.chainId)) return;
    try {
      await wallet.request('wallet_switchEthereumChain', [
        {'chainId': chainId},
      ]);
    } on WalletException catch (e) {
      // 4902: "Unrecognized chain ID". Add it, and the wallet switches.
      if (e.code != 4902 && !e.message.contains('4902') && !e.message.toLowerCase().contains('unrecognized')) {
        rethrow;
      }
      await wallet.request('wallet_addEthereumChain', [
        {
          'chainId': chainId,
          'chainName': network.name,
          'nativeCurrency': {'name': 'Ether', 'symbol': network.symbol, 'decimals': network.decimals},
          'rpcUrls': [network.rpcUrls.first],
          'blockExplorerUrls': [Uri.parse(network.explorerTx).origin],
        },
      ]);
    }
  }

  @override
  Future<void> disconnect() async {
    wallet.provider.removeListener('accountsChanged', _onAccountsChanged);
    // MetaMask and a few others let a site give up its permission.
    try {
      await wallet.request('wallet_revokePermissions', [
        {'eth_accounts': <String, Object>{}},
      ]);
    } on WalletException {
      // Not supported: the wallet keeps the site connected until the user
      // disconnects it there.
    }
  }
}
