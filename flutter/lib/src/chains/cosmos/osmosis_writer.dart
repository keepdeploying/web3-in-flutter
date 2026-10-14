import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../../wallet/in_app_signer.dart';
import '../counter_reader.dart';
import '../counter_writer.dart';

/// Executes the CosmWasm counter with `{"increment":{}}` and friends, in a
/// Cosmos SDK transaction signed in "direct" mode.
class OsmosisWriter extends CounterWriter {
  OsmosisWriter(super.network, super.pool);

  static const denom = 'uosmo';

  @override
  Future<TxResult> send(CounterAction action, InAppSigner signer, {OnTxStep? onStep}) async {
    final watch = Stopwatch()..start();

    // 1. The message: MsgExecuteContract, wrapped in a protobuf Any.
    final executeMsg = jsonEncode({action.name: {}});
    final msg = Proto.any(
      '/cosmwasm.wasm.v1.MsgExecuteContract',
      Proto.message([
        Proto.string(1, signer.address), // sender
        Proto.string(2, network.counter), // contract
        Proto.bytes(3, utf8.encode(executeMsg)), // msg (JSON)
      ]),
    );
    final body = Proto.message([Proto.bytes(1, msg)]);
    onStep?.call(
      TxStep(
        'Build the message',
        detail:
            'MsgExecuteContract from you to the counter contract, with the JSON message below. Cosmos encodes '
            'transactions as protobuf.',
        code: executeMsg,
      ),
    );

    // 2. The account's number and sequence: Cosmos's nonce.
    final account = (await pool.getJson('/cosmos/auth/v1beta1/accounts/${signer.address}'))['account'] as Map;
    final accountNumber = int.parse(account['account_number'] as String);
    final sequence = int.parse(account['sequence'] as String);

    // 3. Simulate to learn the gas, with an empty signature: simulation
    //    doesn't check it.
    final simulation = await pool.postJson('/cosmos/tx/v1beta1/simulate', {
      'tx_bytes': base64Encode(_txRaw(body, _authInfo(signer, sequence, gas: 0, fee: 0), const [])),
    });
    if (simulation['gas_info'] == null) throw TxException('Simulation failed: ${simulation['message']}');
    final gasUsed = int.parse((simulation['gas_info'] as Map)['gas_used'] as String);
    final gas = (gasUsed * 1.4).ceil();
    // Osmosis has a fee market: pay a little over the current base fee.
    final baseFee =
        double.tryParse(
          (await pool.getJson('/osmosis/txfees/v1beta1/cur_eip_base_fee'))['base_fee'] as String? ?? '',
        ) ??
        0.025;
    final fee = (gas * baseFee * 1.5).ceil();
    onStep?.call(
      TxStep(
        'Simulate it',
        detail:
            'Account $accountNumber, sequence $sequence. The simulation used $gasUsed gas; the limit is $gas, '
            'and the fee $fee $denom at ${baseFee.toStringAsFixed(4)} $denom per gas (the current base fee) '
            'with some margin.',
      ),
    );

    // 4. Sign the SignDoc: body, auth info, chain ID and account number.
    final authInfo = _authInfo(signer, sequence, gas: gas, fee: fee);
    final signDoc = Proto.message([
      Proto.bytes(1, body),
      Proto.bytes(2, authInfo),
      Proto.string(3, network.chainId),
      Proto.uint(4, accountNumber),
    ]);
    final signature = signer.signSecp256k1(QuickCrypto.sha256Hash(signDoc));
    final txBytes = _txRaw(body, authInfo, [signature]);
    onStep?.call(
      TxStep(
        'Sign it',
        detail:
            'sha256 of the SignDoc (body, auth info, chain ID ${network.chainId}, account number), signed with '
            'secp256k1, low-S. The chain ID and sequence stop the transaction from being replayed.',
        code: base64Encode(txBytes),
      ),
    );

    // 5. Broadcast, then wait until it is in a block.
    final broadcast = await pool.postJson('/cosmos/tx/v1beta1/txs', {
      'tx_bytes': base64Encode(txBytes),
      'mode': 'BROADCAST_MODE_SYNC',
    });
    final response = broadcast['tx_response'] as Map?;
    if (response == null || response['code'] != 0) {
      throw TxException('The node refused it: ${response?['raw_log'] ?? broadcast['message']}');
    }
    final txId = response['txhash'] as String;
    onStep?.call(TxStep('Send it', detail: 'The node checked it and added it to its mempool.', code: txId));

    final included = await CounterWriter.waitFor(() async {
      final json = await pool.getJsonIfFound('/cosmos/tx/v1beta1/txs/$txId');
      return json?['tx_response'] as Map?;
    });
    if (included['code'] != 0) throw TxException('The contract call failed: ${included['raw_log']}');
    onStep?.call(
      TxStep(
        'Included in block ${included['height']}',
        detail:
            '${included['gas_used']} of $gas gas used. Unused gas is not refunded on Cosmos chains, which is why '
            'the limit comes from a simulation.',
      ),
    );
    return TxResult(txId: txId, elapsed: watch.elapsed);
  }

  /// AuthInfo: who signs (public key, sign mode, sequence) and the fee.
  static List<int> _authInfo(InAppSigner signer, int sequence, {required int gas, required int fee}) {
    final publicKey = Proto.any(
      '/cosmos.crypto.secp256k1.PubKey',
      Proto.message([Proto.bytes(1, signer.key.publicKey)]),
    );
    final signerInfo = Proto.message([
      Proto.bytes(1, publicKey),
      // mode_info.single.mode = SIGN_MODE_DIRECT (1)
      Proto.bytes(
        2,
        Proto.message([
          Proto.bytes(1, Proto.message([Proto.uint(1, 1)])),
        ]),
      ),
      Proto.uint(3, sequence),
    ]);
    final coin = Proto.message([Proto.string(1, denom), Proto.string(2, '$fee')]);
    final feeMessage = Proto.message([Proto.bytes(1, coin), Proto.uint(2, gas)]);
    return Proto.message([Proto.bytes(1, signerInfo), Proto.bytes(2, feeMessage)]);
  }

  /// TxRaw: body bytes, auth info bytes, signatures.
  static List<int> _txRaw(List<int> body, List<int> authInfo, List<List<int>> signatures) => Proto.message([
    Proto.bytes(1, body),
    Proto.bytes(2, authInfo),
    for (final s in signatures) Proto.bytes(3, s),
    if (signatures.isEmpty) Proto.bytes(3, const []),
  ]);
}

/// Just enough protobuf to build a Cosmos transaction.
///
/// Each field is a key (field number and wire type) then the value: a
/// varint for numbers, or a varint length and the bytes for strings,
/// bytes and nested messages. Fields with default values (0, empty) are
/// left out, as protobuf encoders do.
abstract final class Proto {
  static List<int> message(List<List<int>> fields) => [for (final f in fields) ...f];

  static List<int> uint(int field, int value) => value == 0 ? const [] : [..._varint(field << 3), ..._varint(value)];

  static List<int> bytes(int field, List<int> value) => [
    ..._varint(field << 3 | 2),
    ..._varint(value.length),
    ...value,
  ];

  static List<int> string(int field, String value) => value.isEmpty ? const [] : bytes(field, utf8.encode(value));

  /// google.protobuf.Any: a type URL and the encoded message.
  static List<int> any(String typeUrl, List<int> value) => message([string(1, typeUrl), bytes(2, value)]);

  static List<int> _varint(int value) {
    final out = <int>[];
    do {
      var byte = value & 0x7f;
      value >>= 7;
      if (value != 0) byte |= 0x80;
      out.add(byte);
    } while (value != 0);
    return out;
  }
}
