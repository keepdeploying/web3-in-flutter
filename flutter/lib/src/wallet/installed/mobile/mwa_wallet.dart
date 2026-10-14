import 'dart:convert';
import 'dart:ui' show VoidCallback;

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../chains/networks.dart';
import '../../wallet_signer.dart';
import '../installed_wallet.dart';
import 'mwa.dart';

/// Any Solana wallet app on Android that supports the Mobile Wallet
/// Adapter: Phantom, Solflare, Backpack, Seed Vault... Android asks the user
/// which one to open.
class MwaWallet extends InstalledWallet {
  MwaWallet({MobileWalletAdapter? adapter})
    : adapter =
          adapter ??
          MobileWalletAdapter(launch: (uri) => launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication));

  final MobileWalletAdapter adapter;

  /// Who the wallet says is asking, with an icon relative to [identityUri].
  static const identityName = 'Flutter Counter';
  static const identityUri = 'https://github.com/keepdeploying/web3-in-flutter/';
  static const identityIcon = 'raw/main/flutter/assets/icon/favicon.png';

  @override
  String get id => 'mwa';

  @override
  String get name => 'Solana wallet app';

  @override
  String? get icon => null;

  @override
  String get via => 'Mobile Wallet Adapter';

  @override
  Set<ChainFamily> get families => const {ChainFamily.solana};

  /// `authorize` the first time, then again with the token it returned: each
  /// session has to be authorized, and the token lets the wallet skip the
  /// prompt.
  Future<Map<String, dynamic>> authorize(MwaSession session, Network network, {String? authToken}) {
    final identity = {'name': identityName, 'uri': identityUri, 'icon': identityIcon};
    // Wallets older than MWA 2.0 take a cluster name and a separate
    // `reauthorize` method.
    if (session.protocolVersion == 'legacy') {
      return authToken == null
          ? session.call('authorize', {'identity': identity, 'cluster': network.chainId})
          : session.call('reauthorize', {'identity': identity, 'auth_token': authToken});
    }
    return session.call('authorize', {
      'identity': identity,
      'chain': 'solana:${network.chainId}',
      'auth_token': ?authToken,
    });
  }

  /// Runs one session, turning protocol errors into [WalletException]s.
  Future<T> transact<T>(Future<T> Function(MwaSession session) work) async {
    try {
      return await adapter.transact(work);
    } on MwaException catch (e) {
      throw WalletException(
        e.declined ? 'You declined the request in the wallet.' : e.message,
        code: e.code,
        declined: e.declined,
      );
    }
  }

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) => transact((session) async {
    final result = await authorize(session, network);
    final account = (result['accounts'] as List).first as Map<String, dynamic>;
    // MWA sends addresses as base64 of the public key; Solana shows base58.
    final address = Base58Encoder.encode(base64Decode(account['address'] as String));
    return MwaSigner(this, address, result['auth_token'] as String, network);
  });
}

class MwaSigner extends InstalledSigner implements SolanaTransactionSigner {
  MwaSigner(this.wallet, this.address, this._authToken, this._network);

  @override
  final MwaWallet wallet;

  @override
  final String address;

  String _authToken;
  final Network _network;

  @override
  ChainFamily get family => ChainFamily.solana;

  /// Every request is a new session: open the wallet, authorize, ask.
  Future<T> _session<T>(Future<T> Function(MwaSession session) work) => wallet.transact((session) async {
    final result = await wallet.authorize(session, _network, authToken: _authToken);
    _authToken = result['auth_token'] as String? ?? _authToken;
    return work(session);
  });

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) => _session((session) async {
    final result = await session.call('sign_messages', {
      'addresses': [base64Encode(Base58Decoder.decode(address))],
      'payloads': [base64Encode(utf8.encode(message))],
    });
    // Each signed payload is the message with the 64-byte signature after it.
    final signed = base64Decode((result['signed_payloads'] as List).first as String);
    final signature = signed.sublist(signed.length - 64);
    return SignedMessage(
      family: family,
      address: address,
      message: message,
      signature: Base58Encoder.encode(signature),
    );
  });

  @override
  Future<List<int>> signSolanaTransaction(List<int> transaction, Network network) => _session((session) async {
    final result = await session.call('sign_transactions', {
      'payloads': [base64Encode(transaction)],
    });
    return base64Decode((result['signed_payloads'] as List).first as String);
  });
}
