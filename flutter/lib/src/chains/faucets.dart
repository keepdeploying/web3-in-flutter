import 'dart:convert';

import 'package:http/http.dart' as http;

import 'networks.dart';

/// Free test tokens, so a new in-app wallet can pay for transactions.
///
/// Two faucets can be called straight from the app, with no login:
/// - Solana devnet: the `requestAirdrop` RPC method (rate-limited);
/// - NEAR testnet: the faucet API from the NEAR docs.
///
/// The others need a login or a captcha, so the app links to them instead.
abstract final class Faucets {
  /// Only Solana's own devnet endpoint airdrops. The other endpoints in the
  /// pool reject the method, so this call skips the pool.
  static final solanaAirdrop = Uri.parse('https://api.devnet.solana.com');

  /// The NEAR docs' faucet. It sends 5 NEAR per call.
  static final nearFaucet = Uri.parse('https://faucet-near-testnet.onrender.com/api/faucet');

  static bool canFundInApp(Network network) => network == Networks.solanaDevnet || network == Networks.nearTestnet;

  /// What an in-app funding call sends, for the button label.
  static String amount(Network network) => network == Networks.solanaDevnet ? '1 SOL' : '5 NEAR';

  /// Asks the faucet to fund [address]. Returns a line for the UI, and, on
  /// Solana, the airdrop transaction's signature.
  static Future<({String message, String? txId})> fund(Network network, String address, {http.Client? client}) async {
    final httpClient = client ?? http.Client();
    if (network == Networks.solanaDevnet) {
      final response = await httpClient.post(
        solanaAirdrop,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'requestAirdrop',
          // 1 SOL is 10^9 lamports.
          'params': [address, 1000000000],
        }),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['error'] case {'message': final String message}) {
        // Usually the daily limit: "You've either reached your airdrop limit
        // today or the airdrop faucet has run dry..."
        throw Exception(message);
      }
      return (message: 'Airdrop of 1 SOL requested. It lands in a few seconds.', txId: body['result'] as String);
    }
    if (network == Networks.nearTestnet) {
      final response = await httpClient.post(
        nearFaucet,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'accountId': address}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['success'] != true) {
        throw Exception(body['message'] ?? 'Faucet error (HTTP ${response.statusCode})');
      }
      return (message: body['message'] as String, txId: null);
    }
    throw UnsupportedError('No in-app faucet for ${network.name}');
  }
}
