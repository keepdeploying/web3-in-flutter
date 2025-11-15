import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reown_appkit/reown_appkit.dart';

class AuthenticationTab extends StatefulWidget {
  final ReownAppKitModal? appKit;
  final VoidCallback initAppKit;

  const AuthenticationTab({super.key, required this.appKit, required this.initAppKit});

  @override
  State<AuthenticationTab> createState() => _AuthenticationTabState();
}

class _AuthenticationTabState extends State<AuthenticationTab> {
  String? _connectedAddress;
  bool _isConnected = false;
  String _balance = '0.0';
  String _chainType = 'Unknown';
  String _balanceLabel = 'ETH';

  @override
  void initState() {
    super.initState();
    _updateConnectionState();
    _setupEventListeners();
  }

  void _setupEventListeners() {
    if (widget.appKit != null) {
      widget.appKit!.onModalConnect.subscribe((_) => _updateConnectionState());
      widget.appKit!.onModalDisconnect.subscribe((_) => _updateConnectionState());
      widget.appKit!.onModalUpdate.subscribe((_) => _updateConnectionState());
      widget.appKit!.onModalNetworkChange.subscribe((_) => _updateConnectionState());
      widget.appKit!.balanceNotifier.addListener(_onBalanceChange);
    }
  }

  void _onBalanceChange() {
    if (mounted && widget.appKit != null) {
      setState(() => _balance = widget.appKit!.balanceNotifier.value);
    }
  }

  void _updateConnectionState() {
    if (!mounted || widget.appKit == null) return;

    String? address;
    bool connected = widget.appKit!.isConnected;
    String chainType = 'Unknown';
    String balanceLabel = '';

    if (connected && widget.appKit!.session != null) {
      try {
        // Get the current chain ID and namespace
        final chainId = widget.appKit!.selectedChain?.chainId ?? 'eip155:1';
        final namespace = NamespaceUtils.getNamespaceFromChain(chainId);
        address = widget.appKit!.session!.getAddress(namespace);

        // Determine the chain type
        if (chainId.startsWith('solana:')) {
          chainType = 'Solana';
          balanceLabel = 'SOL';
        } else if (chainId.startsWith('eip155:')) {
          chainType = 'Ethereum';
          balanceLabel = 'ETH';
        }
      } catch (e) {
        log('Error getting address: $e');
        address = 'Error getting address';
      }
    }

    setState(() {
      _connectedAddress = address;
      _isConnected = connected;
      _balance = connected ? widget.appKit!.balanceNotifier.value : '0.0';
      _chainType = chainType;
      _balanceLabel = balanceLabel;
    });
  }

  void _showSnackBar(String message) {
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
    final isConnected = _isConnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.account_balance_wallet, color: colorScheme.onPrimaryContainer, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            isConnected ? 'Wallet Connected' : 'Connect Your Wallet',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isConnected ? 'Your wallet is ready to use' : 'Connect your wallet to get started',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Card(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isConnected
                      ? [Colors.green.shade50, Colors.green.shade100]
                      : [colorScheme.surfaceContainerHighest, colorScheme.surfaceContainer],
                ),
              ),
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green.shade100 : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isConnected ? Icons.check_circle : Icons.wallet_outlined,
                      size: 64,
                      color: isConnected ? Colors.green.shade700 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isConnected ? 'Connected' : 'Not Connected',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isConnected ? Colors.green.shade900 : Colors.grey.shade700,
                    ),
                  ),
                  if (_connectedAddress != null) ...[
                    const SizedBox(height: 24),
                    // Chain Type Information
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _chainType == 'Solana' ? Icons.currency_bitcoin : Icons.account_balance,
                            color: _chainType == 'Solana' ? Colors.purple : Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Connected Network',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _chainType,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _chainType == 'Solana' ? Colors.purple : Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Address',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _connectedAddress!));
                                  _showSnackBar('Address copied to clipboard');
                                },
                                tooltip: 'Copy address',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onLongPress: () {
                              Clipboard.setData(ClipboardData(text: _connectedAddress!));
                              _showSnackBar('Address copied to clipboard');
                            },
                            child: Text(
                              '${_connectedAddress!.substring(0, 6)}...${_connectedAddress!.substring(_connectedAddress!.length - 4)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Balance',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_balance $_balanceLabel',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Use the built-in AppKit connect button
          if (widget.appKit != null) ...[
            AppKitModalConnectButton(appKit: widget.appKit!),
            const SizedBox(height: 16),
            Visibility(
              visible: widget.appKit!.isConnected,
              child: AppKitModalAccountButton(appKitModal: widget.appKit!),
            ),
            const SizedBox(height: 16),
            AppKitModalNetworkSelectButton(appKit: widget.appKit!),
          ] else ...[
            FilledButton.icon(
              onPressed: widget.initAppKit,
              icon: const Icon(Icons.refresh),
              label: Text('Refresh'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ],
      ),
    );
  }
}
