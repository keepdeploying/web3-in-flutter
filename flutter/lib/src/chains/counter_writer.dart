import '../rpc/rpc_pool.dart';
import 'chain_family.dart';
import '../wallet/in_app_signer.dart';
import 'counter_reader.dart';
import 'cosmos/osmosis_writer.dart';
import 'evm/evm_writer.dart';
import 'near/near_writer.dart';
import 'networks.dart';
import 'solana/solana_writer.dart';
import 'sui/sui_writer.dart';

/// One step of sending a transaction, for the "What's happening" card.
class TxStep {
  const TxStep(this.title, {this.detail, this.code});

  final String title;
  final String? detail;

  /// Raw data to show: the bytes signed, the hash, the transaction ID.
  final String? code;
}

typedef OnTxStep = void Function(TxStep step);

/// A transaction the network accepted and finished.
class TxResult {
  const TxResult({required this.txId, required this.elapsed});

  final String txId;
  final Duration elapsed;
}

/// Thrown when the network refuses or fails the transaction.
class TxException implements Exception {
  const TxException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Changes the counter with a transaction, the in-app wallet way: build the
/// transaction, sign it with the key, send it, and wait until the network
/// has executed it.
///
/// Every chain does those four things differently. Each subclass is
/// written out in full with no chain SDK, so you can see what a wallet does
/// when you press "Approve".
abstract class CounterWriter {
  CounterWriter(this.network, this.pool);

  final Network network;
  final RpcPool pool;

  Future<TxResult> send(CounterAction action, InAppSigner signer, {OnTxStep? onStep});

  static CounterWriter forNetwork(Network network, RpcPool pool) => switch (network.family) {
    ChainFamily.evm => EvmWriter(network, pool),
    ChainFamily.solana => SolanaWriter(network, pool),
    ChainFamily.sui => SuiWriter(network, pool),
    ChainFamily.cosmos => OsmosisWriter(network, pool),
    ChainFamily.near => NearWriter(network, pool),
  };

  /// Polls [check] until it returns a value, for "wait until included".
  static Future<T> waitFor<T>(
    Future<T?> Function() check, {
    Duration every = const Duration(milliseconds: 1500),
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = await check();
      if (result != null) return result;
      await Future<void>.delayed(every);
    }
    throw const TxException('The transaction was sent, but it was not confirmed in time. Check the explorer.');
  }
}
