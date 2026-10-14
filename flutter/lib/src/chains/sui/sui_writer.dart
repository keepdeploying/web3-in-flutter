import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart' show SuiPersonalMessage, uleb128;

import '../../wallet/in_app_signer.dart';
import '../counter_reader.dart';
import '../counter_writer.dart';
import '../deployments.g.dart';

/// Calls `counter::increment`, `decrement` or `reset` on the shared
/// Registry, in a Sui programmable transaction block.
class SuiWriter extends CounterWriter {
  SuiWriter(super.network, super.pool);

  /// The most the transaction may spend on gas, in MIST (0.01 SUI). It
  /// only pays what it uses.
  static const budget = 10000000;

  @override
  Future<TxResult> send(CounterAction action, InAppSigner signer, {OnTxStep? onStep}) async {
    final watch = Stopwatch()..start();

    // 1. What the transaction needs from the network: the Registry's
    //    initial shared version, the gas price, the epoch, and the chain's
    //    identity (the digest of its first checkpoint).
    final data = await pool.graphql(
      r'''
      query($id: SuiAddress!) {
        object(address: $id) { owner { ... on Shared { initialSharedVersion } } }
        epoch { epochId referenceGasPrice }
        checkpoint(sequenceNumber: 0) { digest }
      }''',
      {'id': Deployments.suiRegistryId},
    );
    final sharedVersion = int.parse('${((data['object'] as Map)['owner'] as Map)['initialSharedVersion']}');
    final epoch = (data['epoch'] as Map)['epochId'] as int;
    final gasPrice = int.parse('${(data['epoch'] as Map)['referenceGasPrice']}');
    final chain = (data['checkpoint'] as Map)['digest'] as String;
    onStep?.call(
      TxStep(
        'Ask the network for the details',
        detail:
            'The Registry is a shared object, first shared at version $sharedVersion. Gas price $gasPrice MIST, '
            'epoch $epoch.',
      ),
    );

    // 2. The transaction, in BCS. Gas is paid from your address balance,
    //    so there are no gas coins to list. Instead, ValidDuring limits it
    //    to this epoch and the next, on this chain, with a random nonce:
    //    that is what stops it from being replayed.
    final transaction = [
      0, // TransactionData::V1
      0, // TransactionKind::ProgrammableTransaction
      ...uleb128(1), // one input:
      1, 1, // CallArg::Object(ObjectArg::SharedObject)
      ..._address(Deployments.suiRegistryId), ..._u64(sharedVersion), 1, // id, initial version, mutable
      ...uleb128(1), // one command:
      0, // Command::MoveCall
      ..._address(Deployments.suiPackageId), ..._string('counter'), ..._string(action.name),
      ...uleb128(0), // no type arguments
      ...uleb128(1), 1, ..._u16(0), // arguments: Input(0), the Registry
      ..._address(signer.address), // sender
      ...uleb128(0), ..._address(signer.address), ..._u64(gasPrice), ..._u64(budget), // gas data
      2, // TransactionExpiration::ValidDuring
      1, ..._u64(epoch), 1, ..._u64(epoch + 1), 0, 0, // min and max epoch, no timestamps
      ...uleb128(32), ...Base58Decoder.decode(chain), // chain
      ..._u32(Random.secure().nextInt(0x100000000)), // nonce
    ];
    onStep?.call(
      TxStep(
        'Build the transaction',
        detail:
            'One MoveCall: ${Deployments.suiPackageId.substring(0, 10)}...::counter::${action.name}(Registry). '
            'The TxContext argument is added by the network. Gas comes from your address balance, budget '
            '${budget / 1e9} SUI.',
        code: base64Encode(transaction),
      ),
    );

    // 3. Sign: blake2b-256 of the intent (transaction data, V0, Sui) and
    //    the bytes, with ed25519.
    final digest = QuickCrypto.blake2b256Hash([0, 0, 0, ...transaction]);
    final signature = SuiPersonalMessage.serialize(signer.signEd25519(digest), signer.key.publicKey);
    onStep?.call(
      TxStep(
        'Sign it',
        detail:
            'Intent [0, 0, 0] (transaction data, version 0, Sui) before the bytes, so a transaction signature '
            'can never pass as a personal message signature, or the other way round.',
        code: signature,
      ),
    );

    // 4. Execute: the network runs it and returns the effects.
    final result = await pool.graphql(
      r'''
      mutation($tx: Base64!, $sigs: [Base64!]!) {
        executeTransaction(transactionDataBcs: $tx, signatures: $sigs) {
          effects { digest status executionError { message } checkpoint { sequenceNumber } }
        }
      }''',
      {
        'tx': base64Encode(transaction),
        'sigs': [signature],
      },
    );
    final effects = (result['executeTransaction'] as Map)['effects'] as Map;
    if (effects['status'] != 'SUCCESS') {
      throw TxException('The transaction failed: ${(effects['executionError'] as Map?)?['message']}');
    }
    final txId = effects['digest'] as String;
    onStep?.call(
      TxStep(
        'Executed',
        detail:
            'Validators ran it and agreed on the effects (finality in about a second). It touched a shared '
            'object, so it went through consensus first.',
        code: txId,
      ),
    );
    return TxResult(txId: txId, elapsed: watch.elapsed);
  }

  static List<int> _address(String hex) => BytesUtils.fromHexString(hex.replaceFirst('0x', '').padLeft(64, '0'));

  static List<int> _string(String value) => [...uleb128(utf8.encode(value).length), ...utf8.encode(value)];

  static List<int> _u16(int value) => (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List();

  static List<int> _u32(int value) => (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

  /// Two 32-bit halves, so it also works on the web (see readU64).
  static List<int> _u64(int value) => [..._u32(value & 0xffffffff), ..._u32(value ~/ 0x100000000)];
}
