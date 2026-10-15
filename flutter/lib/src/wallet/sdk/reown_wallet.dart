import 'dart:async';
import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';

import '../../chains/networks.dart';
import '../installed/installed_wallet.dart';
import '../installed/mobile/deep_links.dart';
import '../wallet_signer.dart';

/// Reown AppKit: one modal that connects hundreds of wallets over
/// WalletConnect, plus Phantom and Solflare through their own links.
///
/// This is the SDK way to do what `installed/` does by hand. AppKit picks
/// the transport (a WalletConnect relay, a deep link, a QR code on another
/// device), keeps the session, and forwards requests. The app still decides
/// what to sign: the same messages and transactions as the other options.
class ReownWallet extends InstalledWallet {
  ReownWallet({required this.navigatorKey, required this.projectId});

  /// The modal is shown on the app's root navigator, which outlives any one
  /// screen.
  final GlobalKey<NavigatorState> navigatorKey;
  final String projectId;

  ReownAppKitModal? _appKit;
  Completer<ReownAppKitModal>? _starting;

  @override
  String get id => 'reown';

  @override
  String get name => 'Reown AppKit';

  @override
  String? get icon => null;

  @override
  String get via => 'WalletConnect';

  @override
  Set<ChainFamily> get families => const {ChainFamily.evm, ChainFamily.solana};

  /// The networks the modal offers: only this app's testnets.
  static List<ReownAppKitModalNetworkInfo> networksFor(String namespace) => [
    for (final network in Networks.all)
      if (_namespaceOf(network) == namespace) _infoOf(network),
  ];

  static String? _namespaceOf(Network network) => switch (network.family) {
    ChainFamily.evm => 'eip155',
    ChainFamily.solana => 'solana',
    _ => null,
  };

  /// CAIP-2 chain IDs: `eip155:84532`, and for Solana the first 32
  /// characters of the genesis hash.
  static String chainIdOf(Network network) => switch (network.family) {
    ChainFamily.solana => 'solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1', // devnet
    _ => 'eip155:${network.chainId}',
  };

  static ReownAppKitModalNetworkInfo _infoOf(Network network) => ReownAppKitModalNetworkInfo(
    name: network.name,
    chainId: chainIdOf(network).split(':').last,
    currency: network.symbol,
    rpcUrl: network.rpcUrls.first,
    explorerUrl: Uri.parse(network.explorerTx).origin,
    isTestNetwork: true,
  );

  Future<ReownAppKitModal> _start() async {
    if (_appKit case final appKit?) return appKit;
    if (_starting case final starting?) return starting.future;
    final starting = _starting = Completer();
    try {
      // AppKit comes with dozens of mainnets. Offer only ours.
      for (final namespace in ReownAppKitModalNetworks.getAllSupportedNamespaces()) {
        ReownAppKitModalNetworks.removeSupportedNetworks(namespace);
      }
      for (final namespace in ['eip155', 'solana']) {
        ReownAppKitModalNetworks.addSupportedNetworks(namespace, networksFor(namespace));
      }
      final appKit = ReownAppKitModal(
        context: navigatorKey.currentState!.overlay!.context,
        projectId: projectId,
        metadata: PairingMetadata(
          name: 'Flutter Counter',
          description: 'Read, sign in and write on testnets from one Flutter app.',
          url: 'https://github.com/keepdeploying/web3-in-flutter',
          icons: ['https://raw.githubusercontent.com/keepdeploying/web3-in-flutter/main/flutter/assets/icon/icon.png'],
          // Wallets come back to the app on this link. DeepLinks hands it
          // to AppKit.
          redirect: Redirect(native: DeepLinks.instance.redirectFor('reown').toString()),
        ),
        disconnectOnDispose: false,
      );
      DeepLinks.instance.forward('reown', (uri) => appKit.dispatchEnvelope(uri.toString()));
      await appKit.init();
      _appKit = appKit;
      starting.complete(appKit);
      return appKit;
    } catch (e, stack) {
      _starting = null;
      starting.completeError(e, stack);
      rethrow;
    }
  }

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) async {
    final appKit = await _start();
    final namespace = _namespaceOf(network)!;
    if (!appKit.isConnected || appKit.session?.getAddress(namespace) == null) {
      await appKit.selectChain(_infoOf(network).copyWith(chainId: chainIdOf(network)));
      // Resolves when the modal closes, connected or not.
      await appKit.openModalView();
    }
    final address = appKit.session?.getAddress(namespace);
    if (!appKit.isConnected || address == null) {
      throw WalletException(
        appKit.isConnected
            ? 'The wallet you connected has no ${network.family.label} account.'
            : 'The modal closed before a wallet connected.',
        declined: !appKit.isConnected,
      );
    }

    void disconnected(ModalDisconnect? _) {
      appKit.onModalDisconnect.unsubscribe(disconnected);
      onLost();
    }

    appKit.onModalDisconnect.subscribe(disconnected);
    return network.family == ChainFamily.evm
        ? ReownEvmSigner(this, appKit, address)
        : ReownSolanaSigner(this, appKit, address);
  }

  /// Sends one request through the session, to the wallet on the other end.
  /// Without a [network], it goes to the chain the session is on.
  Future<dynamic> request(ReownAppKitModal appKit, Network? network, String method, Object params) async {
    try {
      return await appKit.request(
        topic: appKit.session?.topic,
        chainId: network == null ? appKit.selectedChain!.chainId : chainIdOf(network),
        request: SessionRequestParams(method: method, params: params),
      );
    } on JsonRpcError catch (e) {
      // 5000 is WalletConnect's "user rejected".
      throw WalletException(
        e.code == 5000 || e.code == 4001 ? 'You declined the request in the wallet.' : '${e.message}',
        code: e.code,
        declined: e.code == 5000 || e.code == 4001,
      );
    }
  }
}

abstract class _ReownSigner extends InstalledSigner {
  _ReownSigner(this.wallet, this.appKit, this.address);

  @override
  final ReownWallet wallet;
  final ReownAppKitModal appKit;

  @override
  final String address;

  /// The wallet on the other end of the session, by its own name.
  @override
  String get name => appKit.session?.connectedWalletName ?? wallet.name;

  @override
  Future<void> disconnect() => appKit.disconnect();
}

class ReownEvmSigner extends _ReownSigner implements EvmTransactionSender {
  ReownEvmSigner(super.wallet, super.appKit, super.address);

  @override
  ChainFamily get family => ChainFamily.evm;

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    final hex = BytesUtils.toHexString(utf8.encode(message), prefix: '0x');
    // A message signature is the same on every EVM chain, so it goes to
    // whichever chain the session is on.
    final signature = await wallet.request(appKit, null, 'personal_sign', [hex, address]);
    return SignedMessage(family: family, address: address, message: message, signature: '$signature');
  }

  @override
  Future<String> sendEvmTransaction(Network network, {required String to, required String data}) async {
    // The session's chain must be the network's. AppKit asks the wallet to
    // switch, adding the chain if needed.
    if (appKit.selectedChain?.chainId != ReownWallet.chainIdOf(network)) {
      await appKit.selectChain(
        ReownWallet._infoOf(network).copyWith(chainId: ReownWallet.chainIdOf(network)),
        switchChain: true,
      );
    }
    final hash = await wallet.request(appKit, network, 'eth_sendTransaction', [
      {'from': address, 'to': to, 'data': data},
    ]);
    return '$hash';
  }
}

class ReownSolanaSigner extends _ReownSigner implements SolanaTransactionSigner {
  ReownSolanaSigner(super.wallet, super.appKit, super.address);

  @override
  ChainFamily get family => ChainFamily.solana;

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    final result = await wallet.request(appKit, Networks.solanaDevnet, 'solana_signMessage', {
      'pubkey': address,
      'message': Base58Encoder.encode(utf8.encode(message)),
    });
    return SignedMessage(family: family, address: address, message: message, signature: '${result['signature']}');
  }

  @override
  Future<List<int>> signSolanaTransaction(List<int> transaction, Network network) async {
    final result = await wallet.request(appKit, network, 'solana_signTransaction', {
      'transaction': base64Encode(transaction),
    });
    // Wallets answer with the signed transaction, or only the signature.
    if (result['transaction'] case final String signed) return _decode(signed);
    final signature = Base58Decoder.decode('${result['signature']}');
    return [transaction[0], ...signature, ...transaction.sublist(65)];
  }

  /// WalletConnect wallets send base64, Phantom and Solflare base58. Only
  /// base64 uses `+`, `/`, `=`, `0`, `O`, `I` and `l`.
  static List<int> _decode(String text) =>
      RegExp(r'[+/=0OIl]').hasMatch(text) ? base64Decode(text) : Base58Decoder.decode(text);
}
