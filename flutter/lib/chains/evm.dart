import 'package:http/http.dart';
import 'package:web3dart/web3dart.dart';

Future<String?> getEvmChainNativeBalance(String rpcUrl, String symbol, String walletAddress) async {
  final client = Web3Client(rpcUrl, Client());
  final walletEthAddress = EthereumAddress.fromHex(walletAddress);
  final balance = await client.getBalance(walletEthAddress);
  return '${balance.getValueInUnit(EtherUnit.ether)} $symbol';
}

Future<String?> getErc20Balance(String rpcUrl, String tokenAddress, String walletAddress) async {
  final client = Web3Client(rpcUrl, Client());
  final walletEthAddress = EthereumAddress.fromHex(walletAddress);
  final tokenEthAddress = EthereumAddress.fromHex(tokenAddress);
  final abi = ContractAbi.fromJson(
    '[{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"type":"function"}]',
    'ERC20',
  );
  final contract = DeployedContract(abi, tokenEthAddress);
  final function = contract.function('balanceOf');
  final result = await client.call(contract: contract, function: function, params: [walletEthAddress]);
  if (result.isNotEmpty) {
    final (symbol, decimals) = await getErc20Details(client, tokenAddress);
    await client.dispose();
    final balance = ((result[0] as BigInt) / BigInt.from(10).pow(decimals)).toString();
    return '$balance $symbol';
  } else {
    await client.dispose();
    return '';
  }
}

Future<(String, int)> getErc20Details(Web3Client client, String tokenAddress) async {
  final abi = ContractAbi.fromJson(
    '[{"constant":true,"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"type":"function"},'
        '{"constant":true,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"type":"function"}]',
    'ERC20',
  );
  final contract = DeployedContract(abi, EthereumAddress.fromHex(tokenAddress));

  String symbol;
  try {
    final result = await client.call(contract: contract, function: contract.function('symbol'), params: []);
    symbol = result.isNotEmpty ? result[0] as String : '';
  } catch (e) {
    symbol = '';
  }

  int decimals;
  try {
    final result = await client.call(contract: contract, function: contract.function('decimals'), params: []);
    decimals = result.isNotEmpty ? (result[0] as BigInt).toInt() : 0;
  } catch (e) {
    decimals = 0;
  }

  return (symbol, decimals);
}

Future<List<(String hash, String from, DateTime timestamp)>> getLatestEvmTransactions(String rpcUrl) async {
  final List<(String, String, DateTime)> txs = [];
  final client = Web3Client(rpcUrl, Client());
  BigInt current = BigInt.from(await client.getBlockNumber());

  while (txs.length < 10 && current > BigInt.zero) {
    final blockHex = '0x${current.toRadixString(16)}';
    final raw = await client.makeRPCCall('eth_getBlockByNumber', [blockHex, true]);
    final secs = BigInt.parse(raw['timestamp'].toString().replaceFirst('0x', ''), radix: 16);
    final timestamp = DateTime.fromMillisecondsSinceEpoch((secs.toInt() * 1000), isUtc: true);
    for (final tx in raw['transactions']) {
      final hash = tx['hash'] ?? '';
      final from = tx['from'] ?? '0x0000000000000000000000000000000000000000';
      txs.add((hash, from, timestamp));
      if (txs.length == 10) break;
    }
    current -= BigInt.one;
  }
  await client.dispose();
  return txs;
}

// FlutterCounter contract constants
const String flutterCounterAddress = '0x00E5ebC4b76082505F51bd8559c4EB0048f7E90e';
const String flutterCounterAbi = '''[
  {
    "type": "constructor",
    "inputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "decrement",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "increment",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "owner",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "reset",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "totalUsers",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "userCounters",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "int256",
        "internalType": "int256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "userExists",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  }
]''';

// Create FlutterCounter contract instance
DeployedContract createFlutterCounterContract() {
  final abi = ContractAbi.fromJson(flutterCounterAbi, 'FlutterCounter');
  final contractAddress = EthereumAddress.fromHex(flutterCounterAddress);
  return DeployedContract(abi, contractAddress);
}

// Get user counter value from contract
Future<int> getUserCounterValue(String rpcUrl, String userAddress) async {
  final client = Web3Client(rpcUrl, Client());
  final contract = createFlutterCounterContract();
  final userEthAddress = EthereumAddress.fromHex(userAddress);

  try {
    final function = contract.function('userCounters');
    final result = await client.call(contract: contract, function: function, params: [userEthAddress]);

    if (result.isNotEmpty) {
      final counterValue = (result[0] as BigInt).toInt();
      await client.dispose();
      return counterValue;
    }
  } catch (e) {
    print('Error getting user counter: $e');
  }

  await client.dispose();
  return 0;
}

// Get total users count
Future<int> getTotalUsersCount(String rpcUrl) async {
  final client = Web3Client(rpcUrl, Client());
  final contract = createFlutterCounterContract();

  try {
    final function = contract.function('totalUsers');
    final result = await client.call(contract: contract, function: function, params: []);

    if (result.isNotEmpty) {
      final totalUsers = (result[0] as BigInt).toInt();
      await client.dispose();
      return totalUsers;
    }
  } catch (e) {
    print('Error getting total users: $e');
  }

  await client.dispose();
  return 0;
}

// Generate transaction data for increment function
String generateEvmIncrementTxData() {
  final contract = createFlutterCounterContract();
  final function = contract.function('increment');
  final encodedData = function.encodeCall([]);
  return '0x${encodedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
}

// Generate transaction data for decrement function
String generateEvmDecrementTxData() {
  final contract = createFlutterCounterContract();
  final function = contract.function('decrement');
  final encodedData = function.encodeCall([]);
  return '0x${encodedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
}

// Generate transaction data for reset function
String generateEvmResetTxData() {
  final contract = createFlutterCounterContract();
  final function = contract.function('reset');
  final encodedData = function.encodeCall([]);
  return '0x${encodedData.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}';
}
