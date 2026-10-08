// Reads the counter on every network through the app's own readers and RPC
// pools, and prints what it finds. A quick end-to-end check of M5 reads:
//
//   cd flutter && dart run tool/live_reads.dart
// ignore_for_file: avoid_print
import 'package:flutter_counter/src/chains/counter_reader.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/state/services.dart';

/// The public dev wallet's address on each chain family.
const devAddresses = {
  'evm': '0xfFFAa29e82d5455985a908235536d2cD01aCce47',
  'solana': 'DfmTeaToGmhvmzxFA4fCVZJZhdj4HJm2RAvnHSXdkGqX',
  'sui': '0x78c51a7b5ae65f0966b1cad833ee3ef6ededbe9bc6ff4579543c70ff9c67d29e',
  'cosmos': 'osmo1ed3nqhzlm58pzehnajalx4q5wt4zs85p2cud7a',
  'near': '92b28ade98c901eaeb5cd6de863d7b5e9684ca2718c7efd556af051cc4ac5670',
};

Future<void> main() async {
  final services = ChainServices();
  var failures = 0;
  for (final network in Networks.all) {
    final reader = services.reader(network);
    final address = devAddresses[network.family.name]!;
    try {
      final watch = Stopwatch()..start();
      final results = await Future.wait([
        reader.totalUsers(),
        reader.userCounter(address),
        reader.balance(address),
        reader.recentActivity(limit: 3),
      ]);
      final users = results[0] as int;
      final mine = results[1] as UserCounter;
      final balance = results[2] as BigInt;
      final activity = results[3] as List<CounterActivity>;
      print(
        '${network.name.padRight(17)} users=$users dev=${mine.value} (isUser ${mine.isUser}) '
        'balance=${formatUnits(balance, network.decimals)} ${network.symbol} '
        '[${watch.elapsedMilliseconds} ms via ${services.pool(network).lastUsed?.host}]',
      );
      for (final a in activity) {
        print(
          '    ${a.time?.toIso8601String() ?? '?'} ${a.action.name.padRight(9)} ${a.oldValue} -> ${a.newValue} '
          'by ${a.user.substring(0, 10)}... tx ${a.txId.substring(0, 12)}...',
        );
      }
      if (!reader.isValidAddress(address)) throw StateError('address check failed for $address');
    } catch (e) {
      failures++;
      print('${network.name.padRight(17)} FAILED: $e');
    }
  }
  print(failures == 0 ? '\nAll networks read successfully.' : '\n$failures network(s) failed.');
}
