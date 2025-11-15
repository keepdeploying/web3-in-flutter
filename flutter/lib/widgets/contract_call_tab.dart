import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:web3_in_flutter/chains/chains.dart';

class ContractCallTab extends StatefulWidget {
  final ReownAppKitModal? appKit;

  const ContractCallTab({super.key, required this.appKit});

  @override
  State<ContractCallTab> createState() => _ContractCallTabState();
}

class _ContractCallTabState extends State<ContractCallTab> {
  int? _counter;
  String? _lastTransactionHash;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCounterValue();
  }

  Future<void> _loadCounterValue() async {
    if (widget.appKit == null || !widget.appKit!.isConnected) return;

    try {
      final chainId = widget.appKit!.selectedChain?.chainId ?? 'eip155:11155111';
      if (!chainId.startsWith('eip155:11155111')) return; // Only Sepolia supported

      final namespace = NamespaceUtils.getNamespaceFromChain(chainId);
      final address = widget.appKit!.session?.getAddress(namespace);

      if (address != null) {
        final rpcUrl = 'https://sepolia.drpc.org';
        final counterValue = await getUserCounterValue(rpcUrl, address);
        setState(() => _counter = counterValue);
      }
    } catch (e) {
      log('Error loading counter value: $e');
      _showSnackBar('Error loading counter value: $e');
    }
  }

  Future<void> _incrementCounter() async => await _executeContractCall('increment');
  Future<void> _decrementCounter() async => await _executeContractCall('decrement');
  Future<void> _resetCounter() async => await _executeContractCall('reset');

  Future<void> _executeContractCall(String functionName) async {
    if (widget.appKit == null || !widget.appKit!.isConnected) {
      _showSnackBar('Please connect a wallet first');
      return;
    }

    setState(() {
      _isLoading = true;
      _lastTransactionHash = null;
    });

    try {
      final chainId = widget.appKit!.selectedChain?.chainId ?? 'eip155:11155111';
      if (!chainId.startsWith('eip155:11155111')) throw Exception('Please switch to Sepolia network');
      final namespace = NamespaceUtils.getNamespaceFromChain(chainId);
      final address = widget.appKit!.session!.getAddress(namespace);
      if (address == null) throw Exception('No wallet address found');

      final data = switch (functionName) {
        'increment' => generateEvmIncrementTxData(),
        'decrement' => generateEvmDecrementTxData(),
        'reset' => generateEvmResetTxData(),
        _ => throw Exception('Unknown function: $functionName'),
      };

      final transaction = {'from': address, 'to': flutterCounterAddress, 'value': '0x0', 'data': data};
      final result = await widget.appKit!.request(
        topic: widget.appKit!.session!.topic,
        chainId: chainId,
        request: SessionRequestParams(method: 'eth_sendTransaction', params: [transaction]),
      );

      setState(() => _lastTransactionHash = '$result');
      _showSnackBar('Transaction submitted successfully!');
      await Future.delayed(const Duration(seconds: 2));
      await _loadCounterValue();
    } catch (e) {
      log('Error executing contract call: $e');
      _showSnackBar('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = widget.appKit?.isConnected ?? false;

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
                child: Icon(Icons.calculate, color: colorScheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Smart Contract Counter', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(
                      'Interact with a deployed counter smart contract on Sepolia',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (!isConnected)
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Connect to Sepolia testnet to interact with the smart contract',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          if (!isConnected) const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Counter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _isLoading
                        ? CupertinoActivityIndicator(color: colorScheme.onPrimaryContainer)
                        : Text(
                            '${_counter ?? '---'}',
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(color: Colors.red.shade300, borderRadius: BorderRadius.circular(16)),
                        child: IconButton(
                          onPressed: (!_isLoading && isConnected) ? _decrementCounter : null,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.remove),
                          iconSize: 32,
                          color: Colors.white,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.secondary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: (!_isLoading && isConnected) ? _resetCounter : null,
                          icon: _isLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh),
                          iconSize: 32,
                          color: colorScheme.onSecondary,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(color: Colors.lightGreen, borderRadius: BorderRadius.circular(16)),
                        child: IconButton(
                          onPressed: (!_isLoading && isConnected) ? _incrementCounter : null,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.add),
                          iconSize: 32,
                          color: Colors.white,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_lastTransactionHash != null) ...[
            const SizedBox(height: 24),
            Card(
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: colorScheme.onPrimaryContainer, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Transaction Hash',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: SelectableText(
                        _lastTransactionHash!,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Card(
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: colorScheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Important Notes',
                        style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem('Connect to Sepolia testnet to interact with the smart contract'),
                  _buildInfoItem('Counter value is stored on-chain and synced across all users'),
                  _buildInfoItem('Each button calls a function on the deployed FlutterCounter contract'),
                  _buildInfoItem('Contract Address: 0x00E5ebC4b76082505F51bd8559c4EB0048f7E90e'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
