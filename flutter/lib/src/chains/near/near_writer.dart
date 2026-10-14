import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../../wallet/in_app_signer.dart';
import '../../wallet/wallet_signer.dart';
import '../counter_reader.dart';
import '../counter_writer.dart';

/// Calls the NEAR contract's `increment`, `decrement` or `reset` with a
/// FunctionCall action.
class NearWriter extends CounterWriter {
  NearWriter(super.network, super.pool);

  /// 30 TGas, plenty for a counter update. Unused gas is refunded.
  static final gas = BigInt.from(30) * BigInt.from(10).pow(12);

  @override
  Future<TxResult> send(CounterAction action, WalletSigner signer, {OnTxStep? onStep}) async {
    final watch = Stopwatch()..start();
    if (signer is NearFunctionCaller) {
      // An installed wallet builds, signs and sends the transaction itself.
      askToApprove(signer, onStep);
      final txId = await signer.callNearFunction(network, contract: network.counter, method: action.name);
      onStep?.call(
        TxStep(
          'Executed',
          detail:
              '${signer.name} built the FunctionCall (${action.name}, no arguments, no deposit), signed it with '
              'your key and sent it.',
          code: txId,
        ),
      );
      return TxResult(txId: txId, elapsed: watch.elapsed);
    }
    if (signer is! InAppSigner) throw unsupported(signer);

    final publicKey = 'ed25519:${Base58Encoder.encode(signer.key.publicKey)}';

    // Every key has its own nonce; each transaction must use a higher one.
    final accessKey = await pool.jsonRpc('query', {
      'request_type': 'view_access_key',
      'finality': 'final',
      'account_id': signer.address,
      'public_key': publicKey,
    }) as Map;
    final nonce = BigInt.from(accessKey['nonce'] as int) + BigInt.one;
    final blockHash = accessKey['block_hash'] as String;
    onStep?.call(
      TxStep(
        'Ask the network for the details',
        detail:
            'Your key\'s next nonce ($nonce) and a recent block hash, which makes the transaction expire '
            'after about a day.',
        code: blockHash,
      ),
    );

    // Borsh: fields in order, strings and vectors prefixed with a u32
    // length, integers little-endian, enums as a one-byte index.
    final transaction = [
      ..._string(signer.address), // signer
      0, ...signer.key.publicKey, // public key: ed25519 (0) + 32 bytes
      ..._u64(nonce),
      ..._string(network.counter), // receiver: the contract account
      ...Base58Decoder.decode(blockHash),
      ..._u32(1), // one action
      2, // FunctionCall
      ..._string(action.name), // method
      ..._u32(2), ...utf8.encode('{}'), // JSON arguments: none
      ..._u64(gas),
      ..._u128(BigInt.zero), // attached deposit
    ];
    final hash = QuickCrypto.sha256Hash(transaction);
    final signed = [...transaction, 0, ...signer.signEd25519(hash)];
    onStep?.call(
      TxStep(
        'Sign it',
        detail:
            'Borsh-encode signer, key, nonce, receiver ${network.counter}, block hash and one FunctionCall '
            '(${action.name}, no arguments, 30 TGas, no deposit). Sign sha256 of those bytes with ed25519.',
        code: base64Encode(signed),
      ),
    );

    final result = await pool.jsonRpc('send_tx', {
      'signed_tx_base64': base64Encode(signed),
      'wait_until': 'EXECUTED_OPTIMISTIC',
    }) as Map;
    final txId = (result['transaction'] as Map)['hash'] as String;
    final status = result['status'] as Map;
    if (status.containsKey('Failure')) throw TxException('The contract call failed: ${jsonEncode(status['Failure'])}');
    final returned = utf8.decode(base64Decode(status['SuccessValue'] as String? ?? ''));
    onStep?.call(
      TxStep(
        'Executed',
        detail: 'send_tx waited until the call ran. The method returned $returned, your new counter.',
        code: txId,
      ),
    );
    return TxResult(txId: txId, elapsed: watch.elapsed);
  }

  static List<int> _u32(int value) => (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

  /// Little-endian bytes of [value], [length] bytes long. BigInt keeps u64
  /// and u128 exact on the web too.
  static List<int> _le(BigInt value, int length) => [
    for (var i = 0; i < length; i++) ((value >> (8 * i)) & BigInt.from(0xff)).toInt(),
  ];

  static List<int> _u64(BigInt value) => _le(value, 8);
  static List<int> _u128(BigInt value) => _le(value, 16);

  static List<int> _string(String value) {
    final bytes = utf8.encode(value);
    return [..._u32(bytes.length), ...bytes];
  }
}
