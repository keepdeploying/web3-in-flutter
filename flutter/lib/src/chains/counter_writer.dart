import '../rpc/rpc_pool.dart';
import '../wallet/in_app_signer.dart';
import '../wallet/wallet_signer.dart';
import 'counter_reader.dart';
import 'cosmos/osmosis_writer.dart';
import 'evm/evm_writer.dart';
import 'near/near_writer.dart';
import 'networks.dart';
import 'solana/solana_writer.dart';
import 'sui/sui_writer.dart';

/// One step of sending a transaction, for the "What's happening" card.
class TxStep {
  const TxStep(this.title, {this.detail, this.code, this.waitsForUser = false});

  final String title;
  final String? detail;

  /// Whether the app is now waiting for the user to approve in their wallet.
  final bool waitsForUser;

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

/// Changes the counter with a transaction: build it, sign it, send it, and
/// wait until the network has executed it.
///
/// Every chain does those four things differently. Each subclass is
/// written out in full with no chain SDK, so you can see what a wallet does
/// when you press "Approve". With the in-app wallet the app does all four.
/// With an installed wallet it depends on the chain: see the interfaces in
/// `wallet_signer.dart`.
abstract class CounterWriter {
  CounterWriter(this.network, this.pool);

  final Network network;
  final RpcPool pool;

  Future<TxResult> send(CounterAction action, WalletSigner signer, {OnTxStep? onStep});

  /// Tells the user to look at their wallet, unless the app holds the key.
  void askToApprove(WalletSigner signer, OnTxStep? onStep) {
    if (signer is InAppSigner) return;
    onStep?.call(
      TxStep(
        'Approve it in ${signer.name}',
        detail: '${signer.name} shows you the transaction. Nothing is signed until you approve it there.',
        waitsForUser: true,
      ),
    );
  }

  /// For a wallet that can't send this kind of transaction.
  TxException unsupported(WalletSigner signer) =>
      TxException("${signer.name} can't send transactions on ${network.name} from this app.");

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
