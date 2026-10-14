import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter_counter_server/flutter_counter_server.dart';

/// A throwaway EVM key, to sign challenges in tests.
final testPrivateKey = List<int>.generate(32, (i) => i + 1);
final testAddress = EthAddrEncoder().encodeKey(Secp256k1PrivateKey.fromBytes(testPrivateKey).publicKey.compressed);

SignedMessage signEvm(String message, {String? as}) => SignedMessage(
  family: ChainFamily.evm,
  address: as ?? testAddress,
  message: message,
  signature: BytesUtils.toHexString(
    ETHSigner.fromKeyBytes(testPrivateKey).sign(Eip191.hash(message), hashMessage: false).toBytes(),
    prefix: '0x',
  ),
);
