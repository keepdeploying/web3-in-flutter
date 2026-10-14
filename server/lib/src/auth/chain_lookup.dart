import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:http/http.dart' as http;

/// The questions a signature alone can't answer, so the verifier asks the
/// chain:
/// - EVM: smart contract wallets (Safe, Coinbase Smart Wallet...) have no
///   private key. The contract decides whether a signature is valid
///   (ERC-1271).
/// - NEAR: an account can have many keys, and they can change. The chain
///   says whether a key is a full-access key of the account.
/// - Sui: zkLogin signatures (sign in with Google and others) need a full
///   node to check the zero-knowledge proof.
abstract class ChainLookup {
  Future<bool> erc1271IsValid({
    required String chainId,
    required String address,
    required List<int> hash,
    required List<int> signature,
  });

  Future<bool> nearHasFullAccessKey({required String accountId, required String publicKey});

  Future<bool> suiSignatureIsValid({required String message, required String signature, required String address});
}

/// Answers every lookup with "no". For tests, and for offline use where
/// only plain key signatures matter.
class OfflineChainLookup implements ChainLookup {
  const OfflineChainLookup();

  @override
  Future<bool> erc1271IsValid({
    required String chainId,
    required String address,
    required List<int> hash,
    required List<int> signature,
  }) async => false;

  @override
  Future<bool> nearHasFullAccessKey({required String accountId, required String publicKey}) async => false;

  @override
  Future<bool> suiSignatureIsValid({
    required String message,
    required String signature,
    required String address,
  }) async => false;
}

/// Asks public testnet endpoints. Each list is tried in order until one
/// answers, like the app's RPC pool but simpler: the server only makes
/// these calls for the rare signatures that need them.
class RpcChainLookup implements ChainLookup {
  RpcChainLookup({
    http.Client? client,
    Map<String, List<String>>? evmRpcs,
    List<String>? nearRpcs,
    List<String>? suiGraphql,
  }) : _client = client ?? http.Client(),
       evmRpcs = evmRpcs ?? defaultEvmRpcs,
       nearRpcs = nearRpcs ?? const ['https://test.rpc.fastnear.com', 'https://rpc.testnet.near.org'],
       suiGraphql = suiGraphql ?? const ['https://graphql.testnet.sui.io/graphql'];

  final http.Client _client;

  /// RPC endpoints by EVM chain ID.
  final Map<String, List<String>> evmRpcs;
  final List<String> nearRpcs;
  final List<String> suiGraphql;

  static const defaultEvmRpcs = {
    '11155111': ['https://ethereum-sepolia-rpc.publicnode.com', 'https://sepolia.gateway.tenderly.co'],
    '84532': ['https://sepolia.base.org', 'https://base-sepolia-rpc.publicnode.com'],
    '421614': ['https://sepolia-rollup.arbitrum.io/rpc', 'https://arbitrum-sepolia-rpc.publicnode.com'],
    '11155420': ['https://sepolia.optimism.io', 'https://optimism-sepolia-rpc.publicnode.com'],
  };

  /// ERC-1271's magic value: `isValidSignature(bytes32,bytes)` returns its
  /// own selector when the signature is valid.
  static const erc1271MagicValue = '0x1626ba7e';

  @override
  Future<bool> erc1271IsValid({
    required String chainId,
    required String address,
    required List<int> hash,
    required List<int> signature,
  }) async {
    // ABI encoding: the hash, the offset of the bytes argument (0x40), its
    // length, then the signature padded to a multiple of 32 bytes.
    final padded = [...signature, ...List.filled((32 - signature.length % 32) % 32, 0)];
    final data = [
      erc1271MagicValue,
      BytesUtils.toHexString(hash),
      64.toRadixString(16).padLeft(64, '0'),
      signature.length.toRadixString(16).padLeft(64, '0'),
      BytesUtils.toHexString(padded),
    ].join();
    final result = await _jsonRpc(evmRpcs[chainId] ?? const [], 'eth_call', [
      {'to': address, 'data': data},
      'latest',
    ]);
    // A plain account (no code) returns "0x", and a contract that rejects
    // the signature returns anything else, or reverts.
    return result is String && result.toLowerCase().startsWith(erc1271MagicValue);
  }

  @override
  Future<bool> nearHasFullAccessKey({required String accountId, required String publicKey}) async {
    final result = await _jsonRpc(nearRpcs, 'query', {
      'request_type': 'view_access_key',
      'finality': 'final',
      'account_id': accountId,
      'public_key': publicKey,
    });
    // NEP-413 asks for a full-access key: a function-call key only allows
    // calling some contract methods, so it shouldn't prove who you are.
    return result is Map && result['permission'] == 'FullAccess';
  }

  @override
  Future<bool> suiSignatureIsValid({
    required String message,
    required String signature,
    required String address,
  }) async {
    for (final url in suiGraphql) {
      try {
        final response = await _client.post(
          Uri.parse(url),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'query':
                r'query($m: Base64!, $s: Base64!, $a: SuiAddress!) { '
                r'verifySignature(message: $m, signature: $s, intentScope: PERSONAL_MESSAGE, author: $a) { success } }',
            'variables': {'m': base64Encode(utf8.encode(message)), 's': signature, 'a': address},
          }),
        );
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return (json['data']?['verifySignature'] as Map?)?['success'] == true;
      } catch (_) {
        continue; // Try the next endpoint.
      }
    }
    return false;
  }

  /// Returns the JSON-RPC result, or null when the call fails everywhere or
  /// the node answers with an error.
  Future<Object?> _jsonRpc(List<String> urls, String method, Object params) async {
    for (final url in urls) {
      try {
        final response = await _client.post(
          Uri.parse(url),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}),
        );
        if (response.statusCode != 200) continue;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['error'] != null) return null;
        return json['result'];
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
