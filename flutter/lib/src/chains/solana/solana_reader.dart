/// Reads the Anchor counter program on Solana devnet.
///
/// Solana programs keep their data in separate accounts. The counter uses
/// program-derived addresses (PDAs): the Global account at seeds
/// `["global"]` and one Counter account per user at `["counter", user]`.
/// Reading is fetching those accounts and decoding their bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

import '../counter_reader.dart';

class SolanaReader extends CounterReader {
  SolanaReader(super.network, super.pool);

  late final List<int> programId = Base58Decoder.decode(network.counter);

  /// Anchor prefixes every event with the first 8 bytes of
  /// `sha256("event:EventName")`.
  static final counterChangedDiscriminator = QuickCrypto.sha256Hash(utf8.encode('event:CounterChanged')).sublist(0, 8);

  @override
  Future<int> totalUsers() async {
    final data = await _accountData(findProgramAddress([utf8.encode('global')], programId));
    // 8-byte account discriminator, then total_users: u64.
    if (data == null) return 0;
    return readU64(data, 8);
  }

  @override
  Future<UserCounter> userCounter(String address) async {
    final user = Base58Decoder.decode(address);
    final data = await _accountData(findProgramAddress([utf8.encode('counter'), user], programId));
    // 8-byte discriminator, user: Pubkey (32 bytes), value: i64, bump: u8.
    if (data == null) return const UserCounter(value: 0, isUser: false);
    final value = readI64(data, 40);
    return UserCounter(value: value, isUser: true);
  }

  @override
  Future<BigInt> balance(String address) async {
    final result = await pool.jsonRpc('getBalance', [address]) as Map;
    return BigInt.from(result['value'] as int);
  }

  @override
  Future<List<CounterActivity>> recentActivity({int limit = 8}) async {
    final signatures = (await pool.jsonRpc('getSignaturesForAddress', [
      network.counter,
      {'limit': limit * 2},
    ]) as List).cast<Map<String, dynamic>>().where((s) => s['err'] == null).take(limit).toList();

    final transactions = await Future.wait([
      for (final s in signatures)
        pool.jsonRpc('getTransaction', [
          s['signature'],
          {'encoding': 'json', 'maxSupportedTransactionVersion': 0},
        ]),
    ]);

    final activity = <CounterActivity>[];
    for (final (i, tx) in transactions.indexed) {
      if (tx == null) continue;
      final logs = ((tx as Map)['meta']['logMessages'] as List).cast<String>();
      final seconds = tx['blockTime'] as int?;
      for (final line in logs) {
        // Anchor's emit! writes events as base64 in a "Program data:" log.
        if (!line.startsWith('Program data: ')) continue;
        final bytes = base64Decode(line.substring(14));
        if (bytes.length < 57 || !BytesUtils.bytesEqual(bytes.sublist(0, 8), counterChangedDiscriminator)) continue;
        // user (32), old_value (i64), new_value (i64), action (u8 enum index).
        activity.add(
          CounterActivity(
            user: Base58Encoder.encode(bytes.sublist(8, 40)),
            oldValue: readI64(bytes, 40),
            newValue: readI64(bytes, 48),
            action: CounterAction.fromIndex(bytes[56]),
            txId: signatures[i]['signature'] as String,
            time: seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
          ),
        );
      }
    }
    return activity;
  }

  @override
  bool isValidAddress(String address) {
    try {
      return Base58Decoder.decode(address.trim()).length == 32;
    } catch (_) {
      return false;
    }
  }

  @override
  String get howTotalUsersIsRead =>
      'getAccountInfo on the Global account (a PDA from the seed "global"), then read total_users from its bytes.';

  @override
  String get howActivityIsRead =>
      'getSignaturesForAddress on the program, then getTransaction for each, decoding the "Program data:" event logs.';

  @override
  Future<void> checkEndpoints() => pool.checkAll((endpoint, client) async {
    final response = await client.post(
      endpoint,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'getHealth'}),
    );
    if ((jsonDecode(response.body) as Map)['result'] != 'ok') throw StateError('unhealthy');
  });

  Future<List<int>?> _accountData(String address) async {
    final result = await pool.jsonRpc('getAccountInfo', [
      address,
      {'encoding': 'base64'},
    ]) as Map;
    final value = result['value'];
    if (value == null) return null;
    return base64Decode((value['data'] as List).first as String);
  }
}

/// Finds a program-derived address: an address with no private key that only
/// [programId] can sign for.
///
/// It hashes the seeds, a "bump" byte, the program ID and the marker
/// "ProgramDerivedAddress". Valid public keys sit on the ed25519 curve, so
/// a PDA must be off the curve: the bump starts at 255 and counts down until
/// the hash is not a valid public key.
String findProgramAddress(List<List<int>> seeds, List<int> programId) {
  for (var bump = 255; bump >= 0; bump--) {
    final hash = QuickCrypto.sha256Hash([
      for (final seed in seeds) ...seed,
      bump,
      ...programId,
      ...utf8.encode('ProgramDerivedAddress'),
    ]);
    if (!Ed25519PublicKey.isValidBytes(hash)) return Base58Encoder.encode(hash);
  }
  throw StateError('No valid bump found');
}

/// Reads a little-endian u64, the way Borsh (Solana's encoding) stores it.
///
/// `ByteData.getUint64` would be shorter, but it throws on the web: there,
/// Dart ints are JavaScript numbers. Two 32-bit halves work everywhere, and
/// are exact up to 2^53, far beyond any counter.
int readU64(List<int> bytes, int offset) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getUint32(offset + 4, Endian.little) * 0x100000000 + view.getUint32(offset, Endian.little);
}

/// Reads a little-endian i64 (two's complement), web-safe like [readU64].
int readI64(List<int> bytes, int offset) {
  final view = ByteData.sublistView(Uint8List.fromList(bytes));
  return view.getInt32(offset + 4, Endian.little) * 0x100000000 + view.getUint32(offset, Endian.little);
}
