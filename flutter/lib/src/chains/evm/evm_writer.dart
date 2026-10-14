import 'package:blockchain_utils/blockchain_utils.dart';

import '../../wallet/in_app_signer.dart';
import '../../wallet/wallet_signer.dart';
import '../counter_reader.dart';
import '../counter_writer.dart';
import 'evm_reader.dart';

/// Sends `increment()`, `decrement()` or `reset()` to the Solidity counter
/// as an EIP-1559 transaction.
class EvmWriter extends CounterWriter {
  EvmWriter(super.network, super.pool);

  @override
  Future<TxResult> send(CounterAction action, WalletSigner signer, {OnTxStep? onStep}) async {
    final watch = Stopwatch()..start();
    final data = EvmReader.selector('${action.name}()');
    onStep?.call(
      TxStep(
        'Encode the call',
        detail:
            'The data is the 4-byte selector of ${action.name}(): keccak256 of the signature, first 4 bytes. '
            'No arguments, so nothing follows it.',
        code: data,
      ),
    );

    final String txHash;
    if (signer is EvmTransactionSender) {
      // An installed wallet does steps 1 to 3 itself: it picks the nonce,
      // gas and fees, shows them to the user, signs and sends.
      askToApprove(signer, onStep);
      txHash = await signer.sendEvmTransaction(network, to: network.counter, data: data);
      onStep?.call(
        TxStep(
          'Sent by ${signer.name}',
          detail:
              'eth_sendTransaction with only from, to and data. ${signer.name} filled in the nonce, gas and fees, '
              'signed it and sent it to its own RPC node.',
          code: txHash,
        ),
      );
    } else if (signer is InAppSigner) {
      txHash = await _signAndSend(signer, data, onStep);
    } else {
      throw unsupported(signer);
    }

    // 4. Wait for the receipt: the transaction is in a block and executed.
    final receipt = await CounterWriter.waitFor(
      () async => await pool.jsonRpc('eth_getTransactionReceipt', [txHash]) as Map<String, dynamic>?,
    );
    if (receipt['status'] != '0x1') throw const TxException('The transaction reverted.');
    onStep?.call(
      TxStep(
        'Included in block ${_int(receipt['blockNumber'] as String)}',
        detail: 'Status 1 (success), ${_int(receipt['gasUsed'] as String)} gas used.${_changeOf(receipt)}',
      ),
    );
    return TxResult(txId: txHash, elapsed: watch.elapsed);
  }

  /// Steps 1 to 3 with the app's own key.
  Future<String> _signAndSend(InAppSigner signer, String data, OnTxStep? onStep) async {
    final from = signer.address;

    // 1. What the transaction needs from the network.
    final results = await Future.wait([
      pool.jsonRpc('eth_getTransactionCount', [from, 'pending']),
      pool.jsonRpc('eth_getBlockByNumber', ['latest', false]),
      pool.jsonRpc('eth_maxPriorityFeePerGas').catchError((_) => '0x3b9aca00'), // 1 gwei if unsupported
      pool.jsonRpc('eth_estimateGas', [
        {'from': from, 'to': network.counter, 'data': data},
      ]),
    ]);
    final nonce = _int(results[0] as String);
    final baseFee = _int((results[1] as Map)['baseFeePerGas'] as String);
    final tip = _int(results[2] as String);
    // Room for the base fee to double before the transaction gets stuck.
    final maxFee = baseFee * BigInt.two + tip;
    // Estimates can be a little low when state changes between the estimate
    // and the transaction (the first increment also registers the user).
    final gas = _int(results[3] as String) * BigInt.from(12) ~/ BigInt.from(10);
    onStep?.call(
      TxStep(
        'Ask the network for the details',
        detail:
            'Nonce $nonce (your transaction count), gas limit $gas, and fees: up to ${_gwei(maxFee)} gwei per gas, '
            'with a ${_gwei(tip)} gwei tip for the block producer.',
      ),
    );

    // 2. Build and sign: type 2 (EIP-1559) is 0x02 followed by the RLP list.
    final fields = [
      BigInt.parse(network.chainId),
      BigInt.from(nonce.toInt()),
      tip,
      maxFee,
      gas,
      BytesUtils.fromHexString(network.counter),
      BigInt.zero, // value: no ETH sent
      BytesUtils.fromHexString(data),
      <Object>[], // access list
    ];
    final unsigned = [0x02, ...Rlp.encode(fields)];
    final hash = QuickCrypto.keccack256Hash(unsigned);
    final signature = signer.signEvmHash(hash);
    final raw = [
      0x02,
      ...Rlp.encode([...fields, BigInt.from(signature.v - 27), signature.r, signature.s]),
    ];
    final rawHex = BytesUtils.toHexString(raw, prefix: '0x');
    onStep?.call(
      TxStep(
        'Sign it',
        detail:
            'keccak256 of 0x02 + RLP(chain ID, nonce, fees, gas, to, value, data, access list), signed with your key. '
            'The chain ID in the signed bytes stops the same transaction from being replayed on another chain.',
        code: rawHex,
      ),
    );

    // 3. Send.
    final txHash = await pool.jsonRpc('eth_sendRawTransaction', [rawHex]) as String;
    onStep?.call(TxStep('Send it', detail: 'eth_sendRawTransaction returned the transaction hash.', code: txHash));

    return txHash;
  }

  /// The CounterChanged event in the receipt, as text.
  static String _changeOf(Map<String, dynamic> receipt) {
    for (final log in (receipt['logs'] as List).cast<Map<String, dynamic>>()) {
      final topics = log['topics'] as List;
      if (topics.isEmpty || topics.first != EvmReader.counterChangedTopic) continue;
      final data = (log['data'] as String).substring(2);
      BigInt word(int i) => BigInt.parse(data.substring(i * 64, (i + 1) * 64), radix: 16).toSigned(256);
      return ' The CounterChanged event says ${word(0)} to ${word(1)}.';
    }
    return '';
  }

  static BigInt _int(String hex) => BigInt.parse(hex.substring(2), radix: 16);

  static String _gwei(BigInt wei) => (wei.toDouble() / 1e9).toStringAsFixed(wei < BigInt.from(10000000) ? 4 : 2);
}

/// Recursive Length Prefix: how Ethereum serializes transactions.
///
/// Two kinds of items: byte strings and lists. Short items get a one-byte
/// prefix with their length; longer ones get the length of the length.
/// Integers are big-endian bytes with no leading zeros (zero is empty).
abstract final class Rlp {
  static List<int> encode(Object item) {
    // Check bytes first: in Dart a List<int> is also a List<Object>.
    if (item is List<int>) return _string(item);
    if (item is BigInt) return _string(_integer(item));
    if (item is int) return _string(_integer(BigInt.from(item)));
    if (item is List) {
      final body = [for (final element in item) ...encode(element as Object)];
      return [..._length(body.length, 0xc0), ...body];
    }
    throw ArgumentError('RLP encodes bytes, integers and lists, not ${item.runtimeType}');
  }

  static List<int> _string(List<int> bytes) {
    // A single byte below 0x80 is its own encoding.
    if (bytes.length == 1 && bytes[0] < 0x80) return bytes;
    return [..._length(bytes.length, 0x80), ...bytes];
  }

  /// Big-endian, no leading zeros. Zero is the empty string.
  static List<int> _integer(BigInt n) {
    if (n == BigInt.zero) return const [];
    final hex = n.toRadixString(16);
    return BytesUtils.fromHexString(hex.length.isOdd ? '0$hex' : hex);
  }

  static List<int> _length(int length, int offset) {
    if (length < 56) return [offset + length];
    final lengthBytes = _integer(BigInt.from(length));
    return [offset + 55 + lengthBytes.length, ...lengthBytes];
  }
}
