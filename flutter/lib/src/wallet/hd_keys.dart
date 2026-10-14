import 'package:blockchain_utils/blockchain_utils.dart';

import '../chains/chain_family.dart';

export '../chains/chain_family.dart';

/// A key pair derived from a recovery phrase for one chain family.
class ChainKey {
  const ChainKey({
    required this.family,
    required this.path,
    required this.privateKey,
    required this.publicKey,
    required this.address,
  });

  final ChainFamily family;

  /// The BIP-44 style derivation path used, for example `m/44'/60'/0'/0/0`.
  final String path;

  /// Raw 32-byte private key. Treat it like the recovery phrase itself.
  final List<int> privateKey;

  /// Public key bytes in the form each chain expects:
  /// - secp256k1 (EVM, Cosmos): 33-byte compressed key
  /// - ed25519 (Solana, Sui, NEAR): 32-byte key
  final List<int> publicKey;

  /// The account address shown to users.
  final String address;
}

/// Derives keys the same way popular wallets do, so importing the same phrase
/// into MetaMask, Phantom, Slush, Keplr or a NEAR wallet shows the same
/// addresses.
class HdKeys {
  /// Standard derivation path per chain family.
  static const paths = {
    ChainFamily.evm: "m/44'/60'/0'/0/0",
    ChainFamily.solana: "m/44'/501'/0'/0'",
    ChainFamily.sui: "m/44'/784'/0'/0'/0'",
    ChainFamily.cosmos: "m/44'/118'/0'/0/0",
    ChainFamily.near: "m/44'/397'/0'",
  };

  /// Bech32 prefix for Osmosis addresses.
  static const cosmosHrp = 'osmo';

  /// Creates a new random 12-word recovery phrase.
  static String generateMnemonic() => Bip39MnemonicGenerator().fromWordsNumber(Bip39WordsNum.wordsNum12).toStr();

  /// Whether [mnemonic] is a valid BIP-39 phrase (word list and checksum).
  static bool isValidMnemonic(String mnemonic) => Bip39MnemonicValidator().isValid(normalize(mnemonic));

  /// Turns a recovery phrase into the 64-byte BIP-39 seed.
  static List<int> seedFrom(String mnemonic) => Bip39SeedGenerator(Mnemonic.fromString(normalize(mnemonic))).generate();

  /// Derives the key for one chain family from a seed.
  static ChainKey derive(List<int> seed, ChainFamily family) {
    final path = paths[family]!;
    switch (family) {
      case ChainFamily.evm:
      case ChainFamily.cosmos:
        // secp256k1 chains use BIP-32, which allows non-hardened levels.
        final node = Bip32Slip10Secp256k1.fromSeed(seed).derivePath(path);
        final pub = node.publicKey.compressed;
        return ChainKey(
          family: family,
          path: path,
          privateKey: node.privateKey.raw,
          publicKey: pub,
          address: family == ChainFamily.evm
              ? EthAddrEncoder().encodeKey(pub)
              : AtomAddrEncoder().encodeKey(pub, hrp: cosmosHrp),
        );
      case ChainFamily.solana:
      case ChainFamily.sui:
      case ChainFamily.near:
        // ed25519 chains use SLIP-10, where every level must be hardened.
        final node = Bip32Slip10Ed25519.fromSeed(seed).derivePath(path);
        // blockchain_utils prefixes ed25519 public keys with 0x00. Drop it.
        final pub = node.publicKey.compressed.sublist(1);
        final address = switch (family) {
          ChainFamily.solana => SolAddrEncoder().encodeKey(pub),
          ChainFamily.sui => SuiAddrEncoder().encodeKey(pub),
          _ => NearAddrEncoder().encodeKey(pub),
        };
        return ChainKey(family: family, path: path, privateKey: node.privateKey.raw, publicKey: pub, address: address);
    }
  }

  /// Derives keys for every chain family from one recovery phrase.
  static Map<ChainFamily, ChainKey> deriveAll(String mnemonic) {
    final seed = seedFrom(mnemonic);
    return {for (final f in ChainFamily.values) f: derive(seed, f)};
  }

  /// Lowercases the phrase and collapses whitespace to single spaces.
  static String normalize(String mnemonic) => mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
}
