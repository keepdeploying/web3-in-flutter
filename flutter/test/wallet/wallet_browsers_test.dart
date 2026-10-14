import 'package:flutter_counter/src/wallet/installed/mobile/wallet_browsers.dart';
import 'package:flutter_counter/src/wallet/wallet_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("links open the web version in each wallet's browser", () {
    WalletBrowser named(String name) => WalletBrowser.all.firstWhere((b) => b.name == name);
    expect(
      named('MetaMask').linkTo().toString(),
      'https://metamask.app.link/dapp/keepdeploying.github.io/web3-in-flutter/',
    );
    expect(
      named('Phantom').linkTo().toString(),
      'https://phantom.com/ul/browse/https%3A%2F%2Fkeepdeploying.github.io%2Fweb3-in-flutter%2F'
      '?ref=https%3A%2F%2Fkeepdeploying.github.io%2Fweb3-in-flutter%2F',
    );
    expect(named('Keplr').linkTo().toString(), startsWith('keplrwallet://web-browser?url=https%3A%2F%2F'));
  });

  test('each chain lists the wallet browsers that support it', () {
    List<String> names(ChainFamily family) => WalletBrowser.forFamily(family).map((b) => b.name).toList();
    expect(names(ChainFamily.evm), ['MetaMask', 'Phantom']);
    expect(names(ChainFamily.solana), ['Phantom', 'Solflare']);
    expect(names(ChainFamily.cosmos), ['Keplr']);
    expect(names(ChainFamily.near), isEmpty);
  });
}
