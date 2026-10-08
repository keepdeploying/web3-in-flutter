/// Reading the counter, and balances, on any chain.
///
/// Every chain stores the counter differently: EVM contract storage, Solana
/// accounts, a Sui shared object, CosmWasm state, NEAR contract state. Each
/// reader hides that behind the same small interface, so the screens don't
/// care which chain they're showing.
library;

import '../rpc/rpc_pool.dart';
import 'chain_family.dart';
import 'cosmos/osmosis_reader.dart';
import 'evm/evm_reader.dart';
import 'near/near_reader.dart';
import 'networks.dart';
import 'solana/solana_reader.dart';
import 'sui/sui_reader.dart';

/// The three things the counter can do.
enum CounterAction {
  increment('incremented'),
  decrement('decremented'),
  reset('reset');

  const CounterAction(this.pastTense);
  final String pastTense;

  static CounterAction fromIndex(int i) => CounterAction.values[i.clamp(0, 2)];
  static CounterAction fromName(String name) =>
      CounterAction.values.firstWhere((a) => a.name == name, orElse: () => CounterAction.increment);
}

/// One change to someone's counter, decoded from a chain event or log.
class CounterActivity {
  const CounterActivity({
    required this.user,
    required this.action,
    required this.oldValue,
    required this.newValue,
    required this.txId,
    this.time,
  });

  final String user;
  final CounterAction action;
  final int oldValue;
  final int newValue;

  /// The transaction hash, signature or digest, for the explorer link.
  final String txId;
  final DateTime? time;
}

/// One account's counter.
class UserCounter {
  const UserCounter({required this.value, required this.isUser});

  final int value;

  /// Whether the account has ever called the counter.
  final bool isUser;
}

/// Reads the counter and native balances on one network.
abstract class CounterReader {
  CounterReader(this.network, this.pool);

  final Network network;
  final RpcPool pool;

  /// How many accounts have ever used the counter.
  Future<int> totalUsers();

  /// One account's counter. Accounts that never called it read as 0.
  Future<UserCounter> userCounter(String address);

  /// The account's native balance in the smallest unit (wei, lamports, ...).
  Future<BigInt> balance(String address);

  /// The latest counter changes, newest first.
  Future<List<CounterActivity>> recentActivity({int limit = 8});

  /// Whether [address] is a valid account address on this network.
  bool isValidAddress(String address);

  /// A one-line, plain-language description of how each read works, for the
  /// "What's happening" card.
  String get howTotalUsersIsRead;
  String get howActivityIsRead;

  /// Asks one endpoint a cheap question, for the Network status screen.
  Future<void> checkEndpoints();

  static CounterReader forNetwork(Network network, RpcPool pool) => switch (network.family) {
    ChainFamily.evm => EvmReader(network, pool),
    ChainFamily.solana => SolanaReader(network, pool),
    ChainFamily.sui => SuiReader(network, pool),
    ChainFamily.cosmos => OsmosisReader(network, pool),
    ChainFamily.near => NearReader(network, pool),
  };
}

/// Formats an amount in the smallest unit as a decimal string, like
/// `1234500000000000000` wei with 18 decimals as `1.2345`.
String formatUnits(BigInt amount, int decimals, {int maxFraction = 4}) {
  final negative = amount.isNegative;
  final abs = amount.abs();
  final base = BigInt.from(10).pow(decimals);
  final whole = abs ~/ base;
  var fraction = (abs % base).toString().padLeft(decimals, '0');
  if (fraction.length > maxFraction) fraction = fraction.substring(0, maxFraction);
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
}
