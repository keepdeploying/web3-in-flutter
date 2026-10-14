import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter/src/chains/networks.dart';
import 'package:flutter_counter/src/wallet/installed/installed_wallet.dart';
import 'package:flutter_counter/src/wallet/installed/mobile/mwa.dart';
import 'package:flutter_counter/src/wallet/installed/mobile/mwa_wallet.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wallet's side of MWA, enough to test the app's side: a WebSocket
/// server that checks HELLO_REQ, agrees on the session key, and answers
/// authorize, sign_messages and sign_transactions with an ed25519 key.
class FakeMwaWallet {
  FakeMwaWallet({this.decline = false});

  final bool decline;
  final requests = <String>[];
  final _key = List.generate(32, (i) => i + 7);
  late final _signer = Ed25519Signer.fromKeyBytes(_key);
  late final publicKey = Ed25519PrivateKey.fromBytes(_key).publicKey.compressed.sublist(1);

  /// Plays the wallet for the association link the app opens.
  Future<bool> launch(Uri uri) async {
    final token = uri.queryParameters['association']!.replaceAll('_', '/').replaceAll('-', '+').replaceAll('.', '=');
    final association = base64Decode(token);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, int.parse(uri.queryParameters['port']!));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (p) => MobileWalletAdapter.subprotocol,
      );
      List<int>? key;
      var sent = 0;
      List<int> seal(Object message) {
        final seq = (ByteData(4)..setUint32(0, ++sent)).buffer.asUint8List();
        final iv = QuickCrypto.generateRandom(12);
        return [...seq, ...iv, ...GCM(AES(key!)).encrypt(iv, utf8.encode(jsonEncode(message)), associatedData: seq)];
      }

      await for (final data in socket) {
        final bytes = data as List<int>;
        if (key == null) {
          final ecdhPublic = bytes.sublist(0, 65);
          final verifier = Nist256p1Verifier.fromKeyBytes(association);
          expect(
            verifier.verify(QuickCrypto.sha256Hash(ecdhPublic), bytes.sublist(65)),
            isTrue,
            reason: 'HELLO_REQ is signed by the association key',
          );
          final secret = QuickCrypto.generateRandom(32);
          final point = Nist256p1PublicKey.fromBytes(ecdhPublic).point * BigintUtils.fromBytes(secret);
          key = HKDF(
            ikm: BigintUtils.toBytes(point.x, length: 32),
            hash: () => SHA256(),
            length: 16,
            salt: association,
          ).derive();
          socket.add([
            ...Nist256p1PrivateKey.fromBytes(secret).publicKey.uncompressed,
            ...seal({'v': 'v1'}),
          ]);
          continue;
        }
        final plain = GCM(AES(key))
            .decrypt(bytes.sublist(4, 16), bytes.sublist(16), associatedData: bytes.sublist(0, 4))!;
        final request = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        final params = request['params'] as Map<String, dynamic>;
        requests.add(request['method'] as String);
        Object result;
        switch (request['method']) {
          case 'authorize':
            result = {
              'auth_token': 'token-${requests.length}',
              'accounts': [
                {'address': base64Encode(publicKey), 'label': 'Fake'},
              ],
            };
          case _ when decline:
            socket.add(
              seal({
                'jsonrpc': '2.0',
                'id': request['id'],
                'error': {'code': -3, 'message': 'declined'},
              }),
            );
            continue;
          case 'sign_messages':
            final message = base64Decode((params['payloads'] as List).first as String);
            result = {
              'signed_payloads': [
                base64Encode([...message, ..._signer.sign(message)]),
              ],
            };
          default:
            final tx = base64Decode((params['payloads'] as List).first as String);
            result = {
              'signed_payloads': [
                base64Encode([1, ..._signer.sign(tx.sublist(65)), ...tx.sublist(65)]),
              ],
            };
        }
        socket.add(seal({'jsonrpc': '2.0', 'id': request['id'], 'result': result}));
      }
      await server.close();
    });
    return true;
  }
}

void main() {
  test('connects, signs a message the backend accepts, and signs a transaction', () async {
    final fake = FakeMwaWallet();
    final wallet = MwaWallet(
      adapter: MobileWalletAdapter(launch: fake.launch, host: '127.0.0.1'),
    );
    final signer = await wallet.connect(Networks.solanaDevnet, onLost: () {}) as MwaSigner;
    expect(signer.address, Base58Encoder.encode(fake.publicKey));

    final signed = await signer.signMessage('Hello from Flutter Counter!');
    final check = await SignatureVerifier(lookup: const OfflineChainLookup()).verify(signed);
    expect(check.valid, isTrue, reason: check.reason);

    final tx = [1, ...List.filled(64, 0), 9, 8, 7];
    expect((await signer.signSolanaTransaction(tx, Networks.solanaDevnet)).sublist(65), [9, 8, 7]);
    // Each request is its own session, authorized again with the token.
    expect(fake.requests, ['authorize', 'authorize', 'sign_messages', 'authorize', 'sign_transactions']);
  });

  test('a request declined in the wallet says so', () async {
    final fake = FakeMwaWallet(decline: true);
    final wallet = MwaWallet(
      adapter: MobileWalletAdapter(launch: fake.launch, host: '127.0.0.1'),
    );
    final signer = await wallet.connect(Networks.solanaDevnet, onLost: () {});
    await expectLater(
      signer.signMessage('no'),
      throwsA(isA<WalletException>().having((e) => e.declined, 'declined', isTrue)),
    );
  });

  test('with no wallet installed, connecting says so', () async {
    final wallet = MwaWallet(adapter: MobileWalletAdapter(launch: (_) async => false));
    await expectLater(wallet.connect(Networks.solanaDevnet, onLost: () {}), throwsA(isA<WalletException>()));
  });
}
