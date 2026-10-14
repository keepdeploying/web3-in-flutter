// Sends increment, decrement and reset with the dev recovery phrase, and
// checks the counter after each one. Real testnet transactions: they cost a
// little test currency.
//
//   cd flutter && dart run tool/try_writes.dart            # every network
//   cd flutter && dart run tool/try_writes.dart sepolia    # some networks, by ID
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_counter/src/chains/counter_reader.dart';
import 'package:flutter_counter/src/chains/counter_writer.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/state/services.dart';
import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/in_app_signer.dart';

Future<void> main(List<String> args) async {
  final seed = HdKeys.seedFrom(File('../keys/dev-mnemonic.txt').readAsStringSync());
  final services = ChainServices();
  final networks = args.isEmpty ? Networks.all : Networks.all.where((n) => args.contains(n.id)).toList();
  var failures = 0;

  for (final network in networks) {
    final signer = InAppSigner(HdKeys.derive(seed, network.family));
    final reader = services.reader(network);
    final writer = CounterWriter.forNetwork(network, services.pool(network));
    print('\n== ${network.name} as ${signer.address}');
    var expected = (await reader.userCounter(signer.address)).value;
    print('   counter is $expected');

    for (final action in CounterAction.values) {
      expected = switch (action) {
        CounterAction.increment => expected + 1,
        CounterAction.decrement => expected - 1,
        CounterAction.reset => 0,
      };
      try {
        final result = await writer.send(action, signer, onStep: (step) => print('   . ${step.title}'));
        // Reads can lag a moment behind the node that confirmed the write.
        var value = (await reader.userCounter(signer.address)).value;
        for (var i = 0; i < 5 && value != expected; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          value = (await reader.userCounter(signer.address)).value;
        }
        final ok = value == expected;
        if (!ok) failures++;
        print(
          '${ok ? 'OK  ' : 'FAIL'} ${action.name.padRight(9)} -> $value (expected $expected) '
          'in ${result.elapsed.inMilliseconds} ms: ${network.txUrl(result.txId)}',
        );
      } catch (e) {
        failures++;
        print('FAIL ${action.name.padRight(9)} $e');
        break;
      }
    }
  }
  print('\n${failures == 0 ? 'All transactions confirmed.' : '$failures failed.'}');
  exit(failures == 0 ? 0 : 1);
}
