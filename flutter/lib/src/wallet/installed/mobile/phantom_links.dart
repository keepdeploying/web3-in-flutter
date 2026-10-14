import 'dart:convert';
import 'dart:ui' show VoidCallback;

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../chains/networks.dart';
import '../../wallet_signer.dart';
import '../installed_wallet.dart';
import 'deep_links.dart';
import 'nacl_box.dart';

/// Phantom's deep link protocol, which Solflare also speaks.
///
/// Every request is a link to the wallet (`https://phantom.com/ul/v1/...`)
/// and every answer a link back to the app. The first request, `connect`,
/// trades X25519 public keys; from then on each payload is encrypted with
/// [NaclBox], because other apps can read links. The wallet also returns a
/// `session` that later requests send back, so it knows they come from the
/// app the user approved.
class PhantomLinkWallet extends InstalledWallet {
  PhantomLinkWallet._({required this.name, required this.base, required this.scheme, required this.keyParam});

  /// Phantom: links under phantom.com.
  factory PhantomLinkWallet.phantom() => PhantomLinkWallet._(
    name: 'Phantom',
    base: 'https://phantom.com/ul/v1',
    scheme: 'phantom',
    keyParam: 'phantom_encryption_public_key',
  );

  /// Solflare: the same protocol under solflare.com.
  factory PhantomLinkWallet.solflare() => PhantomLinkWallet._(
    name: 'Solflare',
    base: 'https://solflare.com/ul/v1',
    scheme: 'solflare',
    keyParam: 'solflare_encryption_public_key',
  );

  @override
  final String name;

  /// Where the wallet's links start.
  final String base;

  /// The wallet's own URL scheme, used only to see whether it is installed.
  final String scheme;

  /// The query parameter that carries the wallet's public key.
  final String keyParam;

  /// Shown in the wallet's prompt, with the icon it finds there.
  static const appUrl = 'https://github.com/keepdeploying/web3-in-flutter';

  @override
  String get id => 'link:$scheme';

  @override
  String? get icon => null;

  @override
  String get via => 'deep links';

  @override
  Set<ChainFamily> get families => const {ChainFamily.solana};

  /// Opens the wallet with [method] and [params], and waits for its answer.
  /// Returns the answer's query parameters.
  Future<Map<String, String>> request(String method, Map<String, String> params) async {
    final path = '${scheme}_$method';
    final answer = DeepLinks.instance.waitFor(path);
    final link = Uri.parse('$base/$method')
        .replace(queryParameters: {...params, 'redirect_link': DeepLinks.instance.redirectFor(path).toString()});
    if (!await launchUrl(link, mode: LaunchMode.externalApplication)) {
      throw WalletException('Could not open $name.');
    }
    final query = (await answer).queryParameters;
    if (query['errorCode'] case final code?) {
      // 4001: the user said no, as in EIP-1193.
      throw WalletException(
        code == '4001' ? 'You declined the request in $name.' : '$name: ${query['errorMessage'] ?? code}',
        code: code,
        declined: code == '4001',
      );
    }
    return query;
  }

  @override
  Future<InstalledSigner> connect(Network network, {required VoidCallback onLost}) async {
    final keys = NaclBox.newKeyPair();
    final answer = await request('connect', {
      'app_url': appUrl,
      'dapp_encryption_public_key': Base58Encoder.encode(keys.publicKey),
      'cluster': network.chainId, // devnet
    });
    final box = NaclBox.between(keys.secretKey, Base58Decoder.decode(answer[keyParam]!));
    final data = _decrypt(box, answer);
    return PhantomLinkSigner(this, data['public_key'] as String, data['session'] as String, box, keys.publicKey);
  }

  /// Opens the `data` of an answer with the shared key.
  Map<String, dynamic> _decrypt(NaclBox box, Map<String, String> answer) {
    final plain = box.open(Base58Decoder.decode(answer['data']!), Base58Decoder.decode(answer['nonce']!));
    if (plain == null) throw WalletException("$name's answer did not decrypt.");
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }
}

class PhantomLinkSigner extends InstalledSigner implements SolanaTransactionSigner {
  PhantomLinkSigner(this.wallet, this.address, this._session, this._box, this._publicKey);

  @override
  final PhantomLinkWallet wallet;

  @override
  final String address;

  final String _session;
  final NaclBox _box;

  /// Our public key for this session, which every request repeats.
  final List<int> _publicKey;

  @override
  ChainFamily get family => ChainFamily.solana;

  /// Sends [method] with an encrypted [payload] and decrypts the answer.
  Future<Map<String, dynamic>> _call(String method, Map<String, Object> payload) async {
    final nonce = NaclBox.newNonce();
    final sealed = _box.seal(utf8.encode(jsonEncode({...payload, 'session': _session})), nonce);
    final answer = await wallet.request(method, {
      'dapp_encryption_public_key': Base58Encoder.encode(_publicKey),
      'nonce': Base58Encoder.encode(nonce),
      'payload': Base58Encoder.encode(sealed),
    });
    return wallet._decrypt(_box, answer);
  }

  @override
  Future<SignedMessage> signMessage(String message, {List<int>? nearNonce}) async {
    final data = await _call('signMessage', {
      'message': Base58Encoder.encode(utf8.encode(message)),
      // The wallet shows the bytes as text.
      'display': 'utf8',
    });
    return SignedMessage(family: family, address: address, message: message, signature: data['signature'] as String);
  }

  @override
  Future<List<int>> signSolanaTransaction(List<int> transaction, Network network) async {
    final data = await _call('signTransaction', {'transaction': Base58Encoder.encode(transaction)});
    return Base58Decoder.decode(data['transaction'] as String);
  }
}
