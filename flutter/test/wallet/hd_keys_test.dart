import 'package:flutter_counter/src/wallet/hd_keys.dart';
import 'package:flutter_test/flutter_test.dart';

/// The standard BIP-39 test phrase. Never use it for real funds.
const abandon =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  final keys = HdKeys.deriveAll(abandon);

  test('EVM matches the well-known MetaMask address', () {
    expect(keys[ChainFamily.evm]!.address,
        '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
  });

  test('Solana matches the Phantom path', () {
    expect(keys[ChainFamily.solana]!.address,
        'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk');
  });

  // The next three were cross-checked against the official CLIs:
  // `sui keytool import`, `osmosisd keys add --recover` and
  // `near account get-public-key from-seed-phrase`.
  test('Sui matches the Sui CLI', () {
    expect(keys[ChainFamily.sui]!.address,
        '0x5e93a736d04fbb25737aa40bee40171ef79f65fae833749e3c089fe7cc2161f1');
  });

  test('Osmosis matches osmosisd', () {
    expect(keys[ChainFamily.cosmos]!.address,
        'osmo19rl4cm2hmr8afy4kldpxz3fka4jguq0a5m7df8');
  });

  test('NEAR implicit account matches near-cli-rs', () {
    expect(keys[ChainFamily.near]!.address,
        '5510e2b44cae6eb807e3e0e45d579dda058c274abcba15e5cb84636f5d1ee412');
  });

  test('generated phrases are valid 12-word phrases', () {
    final phrase = HdKeys.generateMnemonic();
    expect(phrase.split(' '), hasLength(12));
    expect(HdKeys.isValidMnemonic(phrase), isTrue);
  });
}
