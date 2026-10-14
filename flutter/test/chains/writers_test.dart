import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter/src/chains/counter_reader.dart';
import 'package:flutter_counter/src/chains/counter_writer.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/rpc/rpc_pool.dart';
import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_counter/src/wallet/in_app_signer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const devPhrase = 'someone scrub boss million lesson spread strategy village hello excite celery silent';

/// A JSON-RPC node that answers from [results] and records what was sent.
(RpcPool, List<Map<String, dynamic>>) fakeNode(Network network, Map<String, Object?> results) {
  final calls = <Map<String, dynamic>>[];
  final client = MockClient((request) async {
    final call = jsonDecode(request.body) as Map<String, dynamic>;
    calls.add(call);
    return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': results[call['method']]}), 200);
  });
  return (RpcPool(urls: network.rpcUrls.take(1).toList(), client: client), calls);
}

void main() {
  final seed = HdKeys.seedFrom(devPhrase);

  test('EVM: the raw transaction is an EIP-1559 type 2 signed by the dev key', () async {
    final network = Networks.sepolia;
    final signer = InAppSigner(HdKeys.derive(seed, network.family));
    final (pool, calls) = fakeNode(network, {
      'eth_getTransactionCount': '0x7',
      'eth_getBlockByNumber': {'baseFeePerGas': '0x3b9aca00'},
      'eth_maxPriorityFeePerGas': '0x5f5e100',
      'eth_estimateGas': '0x8000',
      'eth_sendRawTransaction': '0x${'ab' * 32}',
      'eth_getTransactionReceipt': {'status': '0x1', 'blockNumber': '0x10', 'gasUsed': '0x7000', 'logs': <Object>[]},
    });
    final steps = <String>[];
    final result = await CounterWriter.forNetwork(
      network,
      pool,
    ).send(CounterAction.increment, signer, onStep: (s) => steps.add(s.title));
    expect(result.txId, '0x${'ab' * 32}');
    expect(steps.first, 'Encode the call');

    final raw = BytesUtils.fromHexString(
      (calls.firstWhere((c) => c['method'] == 'eth_sendRawTransaction')['params'] as List).first as String,
    );
    expect(raw.first, 2, reason: 'EIP-1559 transactions start with type 0x02');
    // Recover the signer from the signed payload: it must be the dev address.
    final fields = _decodeList(raw.sublist(1));
    expect(fields.length, 12);
    final unsigned = [0x02, ..._encodeList(fields.sublist(0, 9))];
    final r = fields[10], s = fields[11];
    final sig = [
      ...List.filled(32 - r.length, 0),
      ...r,
      ...List.filled(32 - s.length, 0),
      ...s,
      (fields[9].isEmpty ? 0 : fields[9][0]) + 27,
    ];
    final key = ETHVerifier.getPublicKey(QuickCrypto.keccack256Hash(unsigned), sig, hashMessage: false)!;
    expect(EthAddrEncoder().encodeKey(key.toBytes()), signer.address);
    expect(BigintUtils.fromBytes(fields[0]), BigInt.from(11155111), reason: 'chain ID');
    expect(BytesUtils.toHexString(fields[7], prefix: '0x'), EvmReaderSelector.increment);
  });

  test('Solana: the transaction is signed by the user over its message', () async {
    final network = Networks.solanaDevnet;
    final signer = InAppSigner(HdKeys.derive(seed, network.family));
    final (pool, calls) = fakeNode(network, {
      'getLatestBlockhash': {
        'value': {'blockhash': '11111111111111111111111111111111'},
      },
      'sendTransaction': '5sig',
      'getSignatureStatuses': {
        'value': [
          {'confirmationStatus': 'confirmed', 'err': null, 'slot': 1},
        ],
      },
    });
    await CounterWriter.forNetwork(network, pool).send(CounterAction.reset, signer);
    final tx = base64Decode(
      (calls.firstWhere((c) => c['method'] == 'sendTransaction')['params'] as List).first as String,
    );
    expect(tx[0], 1, reason: 'one signature');
    final signature = tx.sublist(1, 65);
    final message = tx.sublist(65);
    expect(message.sublist(0, 3), [1, 0, 2], reason: 'header: 1 signer, 2 read-only accounts');
    expect(Ed25519Verifier.fromKeyBytes(signer.key.publicKey).verify(message, signature), isTrue);
    // The instruction data is Anchor's discriminator for "reset".
    final discriminator = QuickCrypto.sha256Hash(utf8.encode('global:reset')).sublist(0, 8);
    expect(BytesUtils.toHexString(message.sublist(message.length - 8)), BytesUtils.toHexString(discriminator));
  });
}

abstract final class EvmReaderSelector {
  static final increment = BytesUtils.toHexString(
    QuickCrypto.keccack256Hash(utf8.encode('increment()')).sublist(0, 4),
    prefix: '0x',
  );
}

/// A minimal RLP list decoder for the test: one level of byte strings.
List<List<int>> _decodeList(List<int> bytes) {
  var i = 0;
  int length(int prefix, int base) {
    final n = prefix - base;
    if (n < 56) return n;
    final size = n - 55;
    final value = BigintUtils.fromBytes(bytes.sublist(i, i + size)).toInt();
    i += size;
    return value;
  }

  final listPrefix = bytes[i++];
  final end = i + length(listPrefix, 0xc0);
  final items = <List<int>>[];
  while (i < end) {
    final prefix = bytes[i++];
    if (prefix < 0x80) {
      items.add([prefix]);
    } else if (prefix < 0xc0) {
      final n = length(prefix, 0x80);
      items.add(bytes.sublist(i, i + n));
      i += n;
    } else {
      final n = length(prefix, 0xc0);
      items.add(const []); // the empty access list
      i += n;
    }
  }
  return items;
}

List<int> _encodeList(List<List<int>> items) {
  final body = <int>[];
  for (final (index, item) in items.indexed) {
    if (index == 8) {
      body.add(0xc0); // access list
    } else if (item.length == 1 && item[0] < 0x80) {
      body.addAll(item);
    } else {
      body
        ..add(0x80 + item.length)
        ..addAll(item);
    }
  }
  return [0xc0 + body.length, ...body];
}
