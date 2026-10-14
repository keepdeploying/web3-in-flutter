import 'package:flutter/material.dart';
import 'package:flutter_counter/src/chains/evm/evm_address.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/state/connection_controller.dart';
import 'package:flutter_counter/src/ui/widgets/installed_wallet_card.dart';
import 'package:flutter_counter/src/wallet/sdk/sdk_wallets.dart';
import 'package:flutter_counter/src/wallet/wallet_signer.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFinder extends WalletFinder {
  @override
  final wallets = <InstalledWallet>[];

  @override
  void start() {}

  void announce(InstalledWallet wallet) {
    wallets.add(wallet);
    notifyListeners();
  }

  @override
  String noneFoundHint(ChainFamily family) => 'none';
}

class FakeWallet extends InstalledWallet {
  FakeWallet(this.name, this.families, {this.decline = false});

  @override
  final String name;
  @override
  final Set<ChainFamily> families;
  final bool decline;
  VoidCallback? lose;

  @override
  String get id => name;
  @override
  String? get icon => null;
  @override
  String get via => 'test';

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) async {
    if (decline) throw WalletException('You declined the request in $name.', declined: true);
    lose = onLost;
    return FakeSigner(this, network.family);
  }
}

class FakeSigner extends InstalledSigner {
  FakeSigner(this.wallet, this.family);

  @override
  final FakeWallet wallet;
  @override
  final ChainFamily family;
  bool disconnected = false;

  @override
  String get address => '${wallet.name}-address';

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) => throw UnimplementedError();

  @override
  Future<void> disconnect() async => disconnected = true;
}

void main() {
  group('ConnectionController', () {
    test('lists the wallets found for each chain family, as they announce themselves', () {
      final finder = FakeFinder();
      final connections = ConnectionController(finder: finder);
      var changes = 0;
      connections.addListener(() => changes++);

      finder.announce(FakeWallet('MetaMask', {ChainFamily.evm}));
      finder.announce(FakeWallet('Phantom', {ChainFamily.solana, ChainFamily.sui}));

      expect(changes, 2);
      expect(connections.walletsFor(ChainFamily.evm).map((w) => w.name), ['MetaMask']);
      expect(connections.walletsFor(ChainFamily.sui).map((w) => w.name), ['Phantom']);
      expect(connections.walletsFor(ChainFamily.near), isEmpty);
    });

    test('a connected wallet signs for its family until it is disconnected', () async {
      final connections = ConnectionController(finder: FakeFinder());
      await connections.connect(FakeWallet('MetaMask', {ChainFamily.evm}), Networks.baseSepolia);

      final signer = connections.signerFor(ChainFamily.evm) as FakeSigner;
      expect(signer.address, 'MetaMask-address');
      expect(connections.signerFor(ChainFamily.solana), isNull);

      await connections.disconnect(ChainFamily.evm);
      expect(connections.signerFor(ChainFamily.evm), isNull);
      expect(signer.disconnected, isTrue);
    });

    test('connecting another wallet for the same family replaces the first', () async {
      final connections = ConnectionController(finder: FakeFinder());
      await connections.connect(FakeWallet('MetaMask', {ChainFamily.evm}), Networks.sepolia);
      final first = connections.signerFor(ChainFamily.evm) as FakeSigner;
      await connections.connect(FakeWallet('Rabby', {ChainFamily.evm}), Networks.sepolia);

      expect(connections.signerFor(ChainFamily.evm)!.address, 'Rabby-address');
      expect(first.disconnected, isTrue);
    });

    test('a declined connection keeps the message and connects nothing', () async {
      final connections = ConnectionController(finder: FakeFinder());
      await connections.connect(FakeWallet('Phantom', {ChainFamily.solana}, decline: true), Networks.solanaDevnet);

      expect(connections.signerFor(ChainFamily.solana), isNull);
      expect(connections.error, 'You declined the request in Phantom.');
      expect(connections.connecting, isNull);
    });

    test('drops the account when the wallet switches away from it', () async {
      final connections = ConnectionController(finder: FakeFinder());
      final wallet = FakeWallet('MetaMask', {ChainFamily.evm});
      await connections.connect(wallet, Networks.sepolia);

      wallet.lose!();
      expect(connections.signerFor(ChainFamily.evm), isNull);
    });
  });

  test('EIP-55 checksums the addresses wallets return in lower case', () {
    // Test vectors from EIP-55.
    for (final address in [
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
      '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
    ]) {
      expect(toChecksumAddress(address.toLowerCase()), address);
    }
  });

  test('nested SVG elements become groups flutter_svg can draw', () {
    const svg =
        '<svg width="30" height="30" viewBox="0 0 30 30"><svg width="20" height="10" x="5" y="10" '
        'viewBox="0 0 40 20"><path d="M0 0h40v20H0z"/></svg></svg>';
    expect(
      flattenNestedSvg(svg),
      '<svg width="30" height="30" viewBox="0 0 30 30"><g transform="translate(5.0 10.0) scale(0.5 0.5)">'
      '<path d="M0 0h40v20H0z"/></g></svg>',
    );
    // A plain SVG is left as it is.
    const plain = '<svg viewBox="0 0 1 1"><path d="M0 0"/></svg>';
    expect(flattenNestedSvg(plain), plain);
  });

  test('SDK wallets: Intear for NEAR everywhere, Reown AppKit only on phones', () {
    final wallets = sdkWallets(GlobalKey<NavigatorState>());
    expect(wallets.map((w) => w.name), ['Intear Wallet'], reason: 'tests run on a desktop VM');
    expect(wallets.single.families, {ChainFamily.near});
  });
}
