import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';

/// Thrown when the wallet refuses a request or the session fails.
class MwaException implements Exception {
  const MwaException(this.message, {this.code});

  final String message;

  /// The JSON-RPC error code, when the wallet sent one. -3 means the user
  /// declined.
  final int? code;

  bool get declined => code == -3 || code == -1;

  @override
  String toString() => message;
}

/// The Solana Mobile Wallet Adapter protocol, the dapp's side, on Android.
///
/// Unlike Phantom's deep links, which go through the operating system for
/// every request, MWA opens a private channel to the wallet:
///
/// 1. The app makes an association key pair (P-256) and opens
///    `solana-wallet:/v1/associate/local?association=<public key>&port=<p>`.
///    Android shows the wallets that handle it.
/// 2. The wallet starts a WebSocket server on localhost at that port. The
///    app connects and sends HELLO_REQ: a fresh ECDH public key, signed with
///    the association key, so the wallet knows it talks to the app that
///    opened it.
/// 3. The wallet answers with its own ECDH public key. Both sides derive an
///    AES-128-GCM key from the shared secret (HKDF-SHA256, salted with the
///    association public key).
/// 4. From then on, every message is JSON-RPC, encrypted, and numbered:
///    `authorize`, then `sign_messages` or `sign_transactions`.
///
/// One [MwaSession] is one trip to the wallet and back.
class MobileWalletAdapter {
  MobileWalletAdapter({required this.launch, this.host = 'localhost'});

  /// Opens the association link. Returns false if no app handles it.
  final Future<bool> Function(Uri uri) launch;

  /// Where the wallet listens. Tests point this elsewhere.
  final String host;

  /// The WebSocket subprotocol the wallet expects.
  static const subprotocol = 'com.solana.mobilewalletadapter.v1';

  /// Runs [work] in one session with a wallet, then closes it.
  Future<T> transact<T>(Future<T> Function(MwaSession session) work, {int? port}) async {
    final association = _P256Key.random();
    port ??= 49152 + Random.secure().nextInt(16384);
    // Base64 with the characters URLs dislike swapped, as the protocol says.
    final token = base64Encode(association.publicKey).replaceAll('/', '_').replaceAll('+', '-').replaceAll('=', '.');
    final uri = Uri.parse('solana-wallet:/v1/associate/local?association=$token&port=$port&v=v1');
    if (!await launch(uri)) throw const MwaException('No wallet that supports the Mobile Wallet Adapter is installed.');

    final socket = await _connect(port);
    final session = MwaSession._(socket, association);
    try {
      await session._handshake();
      return await work(session);
    } finally {
      await session.close();
    }
  }

  /// The wallet needs a moment to start its server, so keep trying.
  Future<WebSocket> _connect(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      try {
        return await WebSocket.connect('ws://$host:$port/solana-wallet', protocols: [subprotocol]);
      } on Object {
        if (DateTime.now().isAfter(deadline)) {
          throw const MwaException('The wallet did not open a session. Is it a wallet that supports MWA?');
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }
}

/// One encrypted session with a wallet.
class MwaSession {
  MwaSession._(this._socket, this._association) {
    _socket.listen(
      (data) => _incoming.add(Uint8List.fromList(data is String ? utf8.encode(data) : data as List<int>)),
      onError: _incoming.addError,
      onDone: () => _incoming.close(),
    );
  }

  final WebSocket _socket;
  final _P256Key _association;
  final _incoming = StreamController<Uint8List>();
  late final StreamIterator<Uint8List> _messages = StreamIterator(_incoming.stream);

  late List<int> _key;
  int _sent = 0;
  int _received = 0;

  /// "v1" or "legacy": what the wallet said it speaks.
  String protocolVersion = 'legacy';

  Future<Uint8List> _next() async {
    // Empty messages are pings; skip them.
    while (await _messages.moveNext().timeout(const Duration(minutes: 5))) {
      if (_messages.current.isNotEmpty) return _messages.current;
    }
    throw const MwaException('The wallet closed the session.');
  }

  Future<void> _handshake() async {
    final ecdh = _P256Key.random();
    // HELLO_REQ: our ECDH public key, then its ECDSA signature (SHA-256,
    // r and s as 32 bytes each) by the association key.
    _socket.add([...ecdh.publicKey, ..._association.sign(ecdh.publicKey)]);

    // HELLO_RSP: the wallet's ECDH public key, then (wallets that speak v1)
    // the session properties, already encrypted.
    final hello = await _next();
    final shared = ecdh.sharedSecret(hello.sublist(0, 65));
    _key = HKDF(ikm: shared, hash: () => SHA256(), length: 16, salt: _association.publicKey).derive();
    if (hello.length > 65) {
      final properties = jsonDecode(utf8.decode(_decrypt(hello.sublist(65)))) as Map<String, dynamic>;
      protocolVersion = '${properties['v']}' == 'legacy' ? 'legacy' : 'v1';
    }
  }

  /// Sends one JSON-RPC request and returns its result.
  Future<Map<String, dynamic>> call(String method, Map<String, Object?> params) async {
    final id = ++_sent;
    _socket.add(
      _encrypt(id, utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}))),
    );
    final response = jsonDecode(utf8.decode(_decrypt(await _next()))) as Map<String, dynamic>;
    if (response['error'] case final Map<String, dynamic> error) {
      throw MwaException('${error['message']}', code: error['code'] as int?);
    }
    return response['result'] as Map<String, dynamic>;
  }

  /// Sequence number (4 bytes, big-endian), IV (12 bytes), then AES-GCM
  /// ciphertext and tag. The sequence number is also the additional data,
  /// so a message can't be replayed or reordered.
  List<int> _encrypt(int sequence, List<int> plaintext) {
    final seq = _u32(sequence);
    final iv = QuickCrypto.generateRandom(12);
    return [...seq, ...iv, ...GCM(AES(_key)).encrypt(iv, plaintext, associatedData: seq)];
  }

  List<int> _decrypt(List<int> message) {
    final seq = message.sublist(0, 4);
    final sequence = ByteData.sublistView(Uint8List.fromList(seq)).getUint32(0);
    if (sequence != _received + 1) throw const MwaException('A message from the wallet arrived out of order.');
    _received = sequence;
    final plain = GCM(AES(_key)).decrypt(message.sublist(4, 16), message.sublist(16), associatedData: seq);
    if (plain == null) throw const MwaException('A message from the wallet did not decrypt.');
    return plain;
  }

  static List<int> _u32(int value) => (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

  Future<void> close() async {
    await _socket.close();
    await _messages.cancel();
  }
}

/// A P-256 key pair, for the association key (ECDSA) and the session key
/// agreement (ECDH).
class _P256Key {
  _P256Key(this._private) : publicKey = Nist256p1PrivateKey.fromBytes(_private).publicKey.uncompressed;

  factory _P256Key.random() {
    while (true) {
      final bytes = QuickCrypto.generateRandom(32);
      final n = BigintUtils.fromBytes(bytes);
      if (n > BigInt.zero && n < Curves.generator256.order!) return _P256Key(bytes);
    }
  }

  final List<int> _private;

  /// Uncompressed: 0x04, then x and y. 65 bytes.
  final List<int> publicKey;

  /// ECDSA over SHA-256 of [message], as r and s.
  List<int> sign(List<int> message) => Nist256p1Signer.fromKeyBytes(_private).sign(message);

  /// ECDH: the x coordinate of our private key times their public point.
  List<int> sharedSecret(List<int> theirPublicKey) {
    final point = Nist256p1PublicKey.fromBytes(theirPublicKey).point * BigintUtils.fromBytes(_private);
    return BigintUtils.toBytes(point.x, length: 32);
  }
}
