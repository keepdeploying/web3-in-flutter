/// Every network Flutter Counter talks to, and what the app needs to know
/// about each one: how to reach it, how to link to its explorer, and where
/// to get test funds.
library;

import 'chain_family.dart';
import 'deployments.g.dart';

/// One network (a testnet of one chain).
class Network {
  const Network({
    required this.id,
    required this.name,
    required this.family,
    required this.chainId,
    required this.symbol,
    required this.decimals,
    required this.accent,
    required this.logo,
    required this.rpcUrls,
    required this.explorerTx,
    required this.explorerAddress,
    required this.faucetUrl,
    required this.counter,
  });

  /// A stable ID, used in settings and logs. For example `base-sepolia`.
  final String id;

  /// The name shown in the UI. For example `Base Sepolia`.
  final String name;

  final ChainFamily family;

  /// The chain's own identifier: an EVM chain ID like `84532`, a Cosmos
  /// chain ID like `osmo-test-5`, or a cluster name like `devnet`.
  final String chainId;

  /// The native token's symbol, like `ETH` or `SOL`.
  final String symbol;

  /// How many decimals the native token has. 1 ETH is 10^18 wei, 1 SOL is
  /// 10^9 lamports, 1 NEAR is 10^24 yoctoNEAR.
  final int decimals;

  /// The network's brand color as an ARGB integer, so this file stays pure
  /// Dart. The UI turns it into a `Color`.
  final int accent;

  /// The asset path of the network's SVG logo.
  final String logo;

  /// Free public endpoints, in the order the app tries them. Every one was
  /// checked for the right chain, a current head and CORS (for Flutter web).
  final List<String> rpcUrls;

  /// Explorer link templates. `{}` is replaced by the hash or address.
  final String explorerTx;
  final String explorerAddress;

  /// Where to get free test tokens.
  final String faucetUrl;

  /// The counter's address, program ID, object ID or account on this network.
  final String counter;

  bool get isEvm => family == ChainFamily.evm;

  String txUrl(String hash) => explorerTx.replaceFirst('{}', hash);
  String addressUrl(String address) => explorerAddress.replaceFirst('{}', address);

  @override
  String toString() => name;
}

/// All supported networks, in the order the network picker shows them.
abstract final class Networks {
  static const sepolia = Network(
    id: 'sepolia',
    name: 'Sepolia',
    family: ChainFamily.evm,
    chainId: '11155111',
    symbol: 'ETH',
    decimals: 18,
    accent: 0xFF627EEA,
    logo: 'assets/networks/ethereum.svg',
    rpcUrls: [
      'https://sepolia.gateway.tenderly.co',
      'https://rpc.sepolia.ethpandaops.io',
      'https://sepolia.rpc.sentio.xyz',
      'https://eth-sepolia-testnet.api.pocket.network',
      'https://0xrpc.io/sep',
      'https://ethereum-sepolia-rpc.publicnode.com',
    ],
    explorerTx: 'https://sepolia.etherscan.io/tx/{}',
    explorerAddress: 'https://sepolia.etherscan.io/address/{}',
    faucetUrl: 'https://cloud.google.com/application/web3/faucet/ethereum/sepolia',
    counter: Deployments.evmCounter,
  );

  static const baseSepolia = Network(
    id: 'base-sepolia',
    name: 'Base Sepolia',
    family: ChainFamily.evm,
    chainId: '84532',
    symbol: 'ETH',
    decimals: 18,
    accent: 0xFF0052FF,
    logo: 'assets/networks/base.svg',
    rpcUrls: [
      'https://sepolia.base.org',
      'https://base-sepolia.gateway.tenderly.co',
      'https://base-sepolia-rpc.publicnode.com',
      'https://base-sepolia.rpc.sentio.xyz',
      'https://base-sepolia.drpc.org',
    ],
    explorerTx: 'https://sepolia.basescan.org/tx/{}',
    explorerAddress: 'https://sepolia.basescan.org/address/{}',
    faucetUrl: 'https://console.optimism.io/faucet',
    counter: Deployments.evmCounter,
  );

  static const arbitrumSepolia = Network(
    id: 'arbitrum-sepolia',
    name: 'Arbitrum Sepolia',
    family: ChainFamily.evm,
    chainId: '421614',
    symbol: 'ETH',
    decimals: 18,
    accent: 0xFF28A0F0,
    logo: 'assets/networks/arbitrum.svg',
    rpcUrls: [
      'https://sepolia-rollup.arbitrum.io/rpc',
      'https://arbitrum-sepolia.gateway.tenderly.co',
      'https://arbitrum-sepolia-rpc.publicnode.com',
      'https://arbitrum-sepolia.drpc.org',
    ],
    explorerTx: 'https://sepolia.arbiscan.io/tx/{}',
    explorerAddress: 'https://sepolia.arbiscan.io/address/{}',
    faucetUrl: 'https://cloud.google.com/application/web3/faucet/ethereum/sepolia',
    counter: Deployments.evmCounter,
  );

  static const opSepolia = Network(
    id: 'op-sepolia',
    name: 'OP Sepolia',
    family: ChainFamily.evm,
    chainId: '11155420',
    symbol: 'ETH',
    decimals: 18,
    accent: 0xFFFF0420,
    logo: 'assets/networks/optimism.svg',
    rpcUrls: [
      'https://sepolia.optimism.io',
      'https://optimism-sepolia-rpc.publicnode.com',
      'https://optimism-sepolia.gateway.tenderly.co',
      'https://optimism-sepolia.drpc.org',
    ],
    explorerTx: 'https://sepolia-optimism.etherscan.io/tx/{}',
    explorerAddress: 'https://sepolia-optimism.etherscan.io/address/{}',
    faucetUrl: 'https://console.optimism.io/faucet',
    counter: Deployments.evmCounter,
  );

  static const solanaDevnet = Network(
    id: 'solana-devnet',
    name: 'Solana Devnet',
    family: ChainFamily.solana,
    chainId: 'devnet',
    symbol: 'SOL',
    decimals: 9,
    accent: 0xFF9945FF,
    logo: 'assets/networks/solana.svg',
    rpcUrls: [
      'https://api.devnet.solana.com',
      'https://solana-devnet.gateway.tatum.io',
      'https://solana-devnet.api.onfinality.io/public',
    ],
    explorerTx: 'https://explorer.solana.com/tx/{}?cluster=devnet',
    explorerAddress: 'https://explorer.solana.com/address/{}?cluster=devnet',
    faucetUrl: 'https://faucet.solana.com',
    counter: Deployments.solanaProgramId,
  );

  static const suiTestnet = Network(
    id: 'sui-testnet',
    name: 'Sui Testnet',
    family: ChainFamily.sui,
    chainId: 'testnet',
    symbol: 'SUI',
    decimals: 9,
    accent: 0xFF4DA2FF,
    logo: 'assets/networks/sui.svg',
    rpcUrls: ['https://graphql.testnet.sui.io/graphql'],
    explorerTx: 'https://suiscan.xyz/testnet/tx/{}',
    explorerAddress: 'https://suiscan.xyz/testnet/account/{}',
    faucetUrl: 'https://faucet.sui.io/?network=testnet',
    counter: Deployments.suiPackageId,
  );

  static const osmosisTestnet = Network(
    id: 'osmosis-testnet',
    name: 'Osmosis Testnet',
    family: ChainFamily.cosmos,
    chainId: 'osmo-test-5',
    symbol: 'OSMO',
    decimals: 6,
    accent: 0xFF7B2BF9,
    logo: 'assets/networks/osmosis.svg',
    rpcUrls: ['https://lcd.osmotest5.osmosis.zone', 'https://lcd.testnet.osmosis.zone'],
    explorerTx: 'https://celatone.osmosis.zone/osmo-test-5/txs/{}',
    explorerAddress: 'https://celatone.osmosis.zone/osmo-test-5/accounts/{}',
    faucetUrl: 'https://faucet.testnet.osmosis.zone',
    counter: Deployments.osmosisContract,
  );

  static const nearTestnet = Network(
    id: 'near-testnet',
    name: 'NEAR Testnet',
    family: ChainFamily.near,
    chainId: 'testnet',
    symbol: 'NEAR',
    decimals: 24,
    accent: 0xFF00C08B,
    logo: 'assets/networks/near.svg',
    rpcUrls: [
      'https://test.rpc.fastnear.com',
      'https://testnet-rpc.intea.rs',
      'https://near-testnet.drpc.org',
      'https://rpc.testnet.near.org',
    ],
    explorerTx: 'https://testnet.nearblocks.io/txns/{}',
    explorerAddress: 'https://testnet.nearblocks.io/address/{}',
    faucetUrl: 'https://near-faucet.io',
    counter: Deployments.nearContract,
  );

  static const all = [
    sepolia,
    baseSepolia,
    arbitrumSepolia,
    opSepolia,
    solanaDevnet,
    suiTestnet,
    osmosisTestnet,
    nearTestnet,
  ];

  static Network byId(String id) => all.firstWhere((n) => n.id == id, orElse: () => sepolia);
}
