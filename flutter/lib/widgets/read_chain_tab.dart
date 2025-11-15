import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:millisecs/millisecs.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web3_in_flutter/chains/chains.dart';

final _chains = {
  'Sepolia': {'type': 'evm', 'rpc': 'https://sepolia.drpc.org', 'explorer': 'https://sepolia.etherscan.io'},
  'Solana Devnet': {
    'type': 'solana',
    'rpc': 'https://api.devnet.solana.com',
    'explorer': 'https://explorer.solana.com',
  },
  'Sui Testnet': {
    'type': 'sui',
    'rpc': 'https://fullnode.testnet.sui.io:443',
    'explorer': 'https://suiscan.xyz/testnet',
  },
};

class ReadChainTab extends StatefulWidget {
  const ReadChainTab({super.key});

  @override
  State<ReadChainTab> createState() => _ReadChainTabState();
}

class _ReadChainTabState extends State<ReadChainTab> {
  final _addressController = TextEditingController();
  final _tokenAddressController = TextEditingController();
  final _tokenWalletAddressController = TextEditingController();
  String _selectedBalChain = 'Sepolia';
  String _selectedTokenBalChain = 'Sepolia';
  String _selectedTxChain = 'Sepolia';
  String? _nativeBalance;
  String? _tokenBalance;
  bool _isNativeLoading = false;
  bool _isTokenLoading = false;
  List<(String hash, String from, DateTime timestamp)> _transactions = [];
  bool _isLoadingTransactions = false;

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _fetchBalance(String chain) async {
    if (_addressController.text.isEmpty) {
      _showSnackBar('Please enter a wallet address');
      return;
    }

    setState(() {
      _isNativeLoading = true;
      _nativeBalance = null;
    });

    try {
      final address = _addressController.text.trim();
      final chainInfo = _chains[chain]!;
      final chainType = chainInfo['type'] as String;
      final rpcUrl = chainInfo['rpc'] as String;

      String? fetched;
      if (chainType == 'evm') fetched = await getEvmChainNativeBalance(rpcUrl, 'ETH', address);
      if (chainType == 'solana') fetched = await getSolanaBalance(rpcUrl, address);
      if (chainType == 'sui') fetched = await getSuiBalance(rpcUrl, address);

      setState(() {
        _nativeBalance = fetched;
        _isNativeLoading = false;
      });
    } catch (e) {
      setState(() {
        _nativeBalance = 'Error: $e';
        _isNativeLoading = false;
      });
      _showSnackBar('Error fetching balance: $e');
      log('Error fetching balance: $e');
    }
  }

  Future<void> _fetchTokenBalance(String chain) async {
    if (_tokenWalletAddressController.text.isEmpty) {
      _showSnackBar('Please enter a wallet address');
      return;
    }

    if (_tokenAddressController.text.isEmpty) {
      _showSnackBar('Please enter a token address');
      return;
    }

    setState(() {
      _isTokenLoading = true;
      _tokenBalance = null;
    });

    try {
      final walletAddress = _tokenWalletAddressController.text.trim();
      final tokenAddress = _tokenAddressController.text.trim();
      final chainInfo = _chains[chain]!;
      final chainType = chainInfo['type'] as String;
      final rpcUrl = chainInfo['rpc'] as String;

      String? fetched;
      if (chainType == 'evm') fetched = await getErc20Balance(rpcUrl, tokenAddress, walletAddress);
      if (chainType == 'solana') fetched = await getSplTokenBalance(rpcUrl, tokenAddress, walletAddress);
      if (chainType == 'sui') fetched = await getSuiBalance(rpcUrl, walletAddress, tokenAddress);
      setState(() {
        _tokenBalance = fetched;
        _isTokenLoading = false;
      });
    } catch (e) {
      setState(() {
        _tokenBalance = 'Error: $e';
        _isTokenLoading = false;
      });
      _showSnackBar('Error fetching token balance: $e');
      log('Error fetching token balance: $e');
    }
  }

  Future<void> fetchTransactions(String chain) async {
    setState(() {
      _transactions = [];
      _isLoadingTransactions = true;
    });

    try {
      final chainInfo = _chains[chain]!;
      final chainType = chainInfo['type'] as String;
      final rpcUrl = chainInfo['rpc'] as String;

      List<(String hash, String from, DateTime timestamp)> txs = [];
      if (chainType == 'evm') txs = await getLatestEvmTransactions(rpcUrl);
      if (chainType == 'solana') txs = await getLatestSolanaTransactions(rpcUrl);
      if (chainType == 'sui') txs = await getLatestSuiTransactions(rpcUrl);

      setState(() {
        _transactions = txs;
        _isLoadingTransactions = false;
      });
    } catch (e) {
      setState(() {
        _transactions = [];
        _isLoadingTransactions = false;
      });
      log('Error fetching transactions: $e');
      _showSnackBar('Error fetching transactions: ${e.toString()}');
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    _tokenAddressController.dispose();
    _tokenWalletAddressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.account_balance, color: colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Check Balance', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('View wallet balance for selected chain', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wallet Address',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _addressController,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(hintText: '0x742d3...', prefixIcon: Icon(Icons.wallet)),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Select Chain',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _ChainChooser(
                    selectedChain: _selectedBalChain,
                    onChanged: (String? newValue) {
                      if (newValue != null) setState(() => _selectedBalChain = newValue);
                    },
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isNativeLoading ? null : () => _fetchBalance(_selectedBalChain),
                      icon: _isNativeLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.search),
                      label: Text(_isNativeLoading ? 'Fetching...' : 'Fetch Balance'),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_nativeBalance != null) ...[
            const SizedBox(height: 24),
            Card(
              color: _nativeBalance!.startsWith('Error') ? colorScheme.errorContainer : colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _nativeBalance!.startsWith('Error') ? Icons.error_outline : Icons.account_balance_wallet,
                          color: _nativeBalance!.startsWith('Error')
                              ? colorScheme.onErrorContainer
                              : colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _nativeBalance!.startsWith('Error') ? 'Error' : 'Balance',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _nativeBalance!.startsWith('Error')
                                ? colorScheme.onErrorContainer
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _nativeBalance!,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _nativeBalance!.startsWith('Error')
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          // Token Balance Section
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.account_balance_wallet, color: colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Token Balance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wallet Address',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenWalletAddressController,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(hintText: '0x742d...', prefixIcon: Icon(Icons.wallet, size: 20)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Select Chain',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _ChainChooser(
                    selectedChain: _selectedTokenBalChain,
                    onChanged: (String? newValue) {
                      if (newValue != null) setState(() => _selectedTokenBalChain = newValue);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Token Address',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenAddressController,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(hintText: '0x...', prefixIcon: Icon(Icons.token, size: 20)),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isTokenLoading ? null : () => _fetchTokenBalance(_selectedTokenBalChain),
                      icon: _isTokenLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.search, size: 18),
                      label: Text(
                        _isTokenLoading ? 'Fetching...' : 'Fetch Token Balance',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_tokenBalance != null) ...[
            const SizedBox(height: 16),
            Card(
              color: _tokenBalance!.startsWith('Error') ? colorScheme.errorContainer : colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _tokenBalance!.startsWith('Error') ? Icons.error_outline : Icons.token,
                          color: _tokenBalance!.startsWith('Error')
                              ? colorScheme.onErrorContainer
                              : colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _tokenBalance!.startsWith('Error') ? 'Error' : 'Token Balance',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _tokenBalance!.startsWith('Error')
                                ? colorScheme.onErrorContainer
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _tokenBalance!,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _tokenBalance!.startsWith('Error')
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),

          // Latest Transactions Section
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.history, color: colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Latest Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Chain',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _ChainChooser(
                    selectedChain: _selectedTxChain,
                    onChanged: (String? newValue) {
                      if (newValue != null) setState(() => _selectedTxChain = newValue);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: (_isLoadingTransactions) ? null : () => fetchTransactions(_selectedTxChain),
                      icon: _isLoadingTransactions
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: Text(
                        _isLoadingTransactions ? 'Loading...' : 'Fetch Transactions',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    ),
                  ),
                  if (_transactions.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    ..._transactions.map(
                      (tx) => InkWell(
                        onTap: () => launchUrlString(
                          '${_chains[_selectedTxChain]?['explorer']}/tx/${tx.$1}'
                          '${_selectedTxChain == 'Solana Devnet' ? '?cluster=devnet' : ''}',
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.receipt_long, size: 18, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Tx: ${tx.$1}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Sender: ${tx.$2}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: StatefulBuilder(
                                  builder: (context, setState) {
                                    Timer.periodic(const Duration(seconds: 1), (_) {
                                      if (context.mounted) setState(() {});
                                    });

                                    return Text(
                                      ms(DateTime.now().difference(tx.$3).inMilliseconds),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange.shade700,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else if (!_isLoadingTransactions) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: Text('No transactions found', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChainChooser extends StatelessWidget {
  const _ChainChooser({required this.selectedChain, required this.onChanged});

  final String selectedChain;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: selectedChain,
      decoration: const InputDecoration(prefixIcon: Icon(Icons.public, size: 20)),
      items: _chains.keys.map((String chain) {
        final chainType = _chains[chain]!['type'] as String;
        return DropdownMenuItem(
          value: chain,
          child: Row(
            children: [
              Text(chain, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: chainType == 'evm'
                      ? Colors.blue.shade50
                      : chainType == 'solana'
                      ? Colors.purple.shade50
                      : Colors.cyan.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  chainType.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    color: chainType == 'evm'
                        ? Colors.blue.shade700
                        : chainType == 'solana'
                        ? Colors.purple.shade700
                        : Colors.cyan.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
