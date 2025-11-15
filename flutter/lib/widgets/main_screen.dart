import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:web3_in_flutter/widgets/authentication_tab.dart';
import 'package:web3_in_flutter/widgets/contract_call_tab.dart';
import 'package:web3_in_flutter/widgets/read_chain_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  ReownAppKitModal? _appKit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async => await _initializeAppKit());
  }

  Future<void> _initializeAppKit() async {
    try {
      final projectId = dotenv.env['REOWN_PROJECT_ID'] ?? '';
      if (projectId.isEmpty) throw Exception('REOWN_PROJECT_ID not found in .env file');

      _appKit = ReownAppKitModal(
        context: context,
        projectId: projectId,
        metadata: const PairingMetadata(
          name: 'Web3 In Flutter',
          description: 'Getting started with Web3 in Flutter Workshop',
          url: 'https://flutter.dev',
          icons: ['https://storage.googleapis.com/cms-storage-bucket/icon_flutter.0dbfcc7a59cd1cf16282.png'],
          redirect: Redirect(native: 'fluttercounter://', linkMode: false),
        ),
        featuredWalletIds: const {
          'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // MetaMask
          'a797aa35c0fadbfc1a53e7f675162ed5226968b44a19ee3d24385c64d1d3c393', // Phantom (Solana)
          '1ca0bdd4747578705b1939af023d120677c64fe6ca76add81fda36e350605e79', // Solflare (Solana)
          '4622a2b2d6af1c9844944291e5e7351a6aa24cd7b23099efac1b2fd875da31a0', // Trust Wallet
        },
      );

      await _appKit!.init();
      log('adfs');
      setState(() {});
    } catch (e) {
      log('Error initializing Reown AppKit: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colorScheme.surface, colorScheme.surfaceContainerHighest],
          ),
        ),
        child: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: [
              ReadChainTab(),
              AuthenticationTab(appKit: _appKit, initAppKit: _initializeAppKit),
              ContractCallTab(appKit: _appKit),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        height: 100,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -5)),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.zero,
          child: NavigationBar(
            selectedIndex: _currentIndex,
            height: 80,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.visibility_outlined, size: 22),
                selectedIcon: Icon(Icons.visibility, size: 22),
                label: 'Read',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined, size: 22),
                selectedIcon: Icon(Icons.account_balance_wallet, size: 22),
                label: 'Authentication',
              ),
              NavigationDestination(
                icon: Icon(Icons.edit_note_outlined, size: 22),
                selectedIcon: Icon(Icons.edit_note, size: 22),
                label: 'Contract',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
