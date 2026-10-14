import '../../wallet_signer.dart';

/// Where the web version of this app is published (scripts/deploy-pages.sh).
const webAppUrl = 'https://keepdeploying.github.io/web3-in-flutter/';

/// A wallet app with a built-in browser that can open the web version.
///
/// For most chains, a native app has no way to reach a wallet app without
/// an SDK. But wallet apps have browsers that inject the same objects
/// extensions do (EIP-6963, the Wallet Standard, window.keplr). Opened
/// there, the web version finds the wallet as it does on a desktop.
class WalletBrowser {
  const WalletBrowser(this.name, this.families, this._link);

  final String name;
  final Set<ChainFamily> families;
  final Uri Function(String url) _link;

  /// The link that opens [url] in this wallet's browser.
  Uri linkTo([String url = webAppUrl]) => _link(url);

  static final all = [
    WalletBrowser('MetaMask', const {ChainFamily.evm}, _metaMask),
    WalletBrowser('Phantom', const {ChainFamily.solana, ChainFamily.evm}, _phantom),
    WalletBrowser('Solflare', const {ChainFamily.solana}, _solflare),
    WalletBrowser('Keplr', const {ChainFamily.cosmos}, _keplr),
  ];

  static Uri _metaMask(String url) =>
      Uri.parse('https://metamask.app.link/dapp/${url.replaceFirst(RegExp('^https?://'), '')}');

  static Uri _phantom(String url) =>
      Uri.parse('https://phantom.com/ul/browse/${Uri.encodeComponent(url)}?ref=${Uri.encodeComponent(url)}');

  static Uri _solflare(String url) =>
      Uri.parse('https://solflare.com/ul/v1/browse/${Uri.encodeComponent(url)}?ref=${Uri.encodeComponent(url)}');

  static Uri _keplr(String url) => Uri.parse('keplrwallet://web-browser?url=${Uri.encodeComponent(url)}');

  static List<WalletBrowser> forFamily(ChainFamily family) => [
    for (final browser in all)
      if (browser.families.contains(family)) browser,
  ];
}
