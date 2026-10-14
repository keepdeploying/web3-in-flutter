import 'dart:convert';

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
        final privateKey = bip32Secp256k1(seed, parsePath(path));
        final pub = Secp256k1PrivateKey.fromBytes(privateKey).publicKey.compressed;
        return ChainKey(
          family: family,
          path: path,
          privateKey: privateKey,
          publicKey: pub,
          address: family == ChainFamily.evm
              ? EthAddrEncoder().encodeKey(pub)
              : AtomAddrEncoder().encodeKey(pub, hrp: cosmosHrp),
        );
      case ChainFamily.solana:
      case ChainFamily.sui:
      case ChainFamily.near:
        final privateKey = slip10Ed25519(seed, parsePath(path));
        // blockchain_utils prefixes ed25519 public keys with 0x00. Drop it.
        final pub = Ed25519PrivateKey.fromBytes(privateKey).publicKey.compressed.sublist(1);
        final address = switch (family) {
          ChainFamily.solana => SolAddrEncoder().encodeKey(pub),
          ChainFamily.sui => SuiAddrEncoder().encodeKey(pub),
          _ => NearAddrEncoder().encodeKey(pub),
        };
        return ChainKey(family: family, path: path, privateKey: privateKey, publicKey: pub, address: address);
    }
  }

  /// Hardened indexes have the top bit set, written with an apostrophe.
  static const hardened = 0x80000000;

  /// "m/44'/60'/0'/0/0" to [44 | hardened, 60 | hardened, 0 | hardened, 0, 0].
  static List<int> parsePath(String path) => [
    for (final part in path.split('/').skip(1))
      part.endsWith("'") ? int.parse(part.substring(0, part.length - 1)) | hardened : int.parse(part),
  ];

  /// SLIP-10 for ed25519 (Solana, Sui, NEAR).
  ///
  /// Every level must be hardened, so each step is one HMAC-SHA512 of the
  /// parent key: no curve math at all until the final public key. Libraries
  /// that compute a public key at every level (for fingerprints a wallet
  /// never shows) are several times slower, which you feel on the web.
  static List<int> slip10Ed25519(List<int> seed, List<int> path) {
    var (key, chainCode) = _split(QuickCrypto.hmacSha512Hash(utf8.encode('ed25519 seed'), seed));
    for (final index in path) {
      if (index < hardened) throw ArgumentError('ed25519 paths must be hardened: $path');
      (key, chainCode) = _split(QuickCrypto.hmacSha512Hash(chainCode, [0, ...key, ..._u32(index)]));
    }
    return key;
  }

  /// BIP-32 for secp256k1 (EVM, Cosmos).
  ///
  /// A hardened step hashes the parent private key. A normal step hashes the
  /// parent public key instead, which is what lets a watch-only wallet derive
  /// addresses without private keys. Either way the child key is
  /// (left half of the hash + parent key) mod n.
  static List<int> bip32Secp256k1(List<int> seed, List<int> path) {
    final n = Curves.generatorSecp256k1.order!;
    var (key, chainCode) = _split(QuickCrypto.hmacSha512Hash(utf8.encode('Bitcoin seed'), seed));
    for (final index in path) {
      final data = index >= hardened
          ? [0, ...key, ..._u32(index)]
          : [...Secp256k1PrivateKey.fromBytes(key).publicKey.compressed, ..._u32(index)];
      final (left, right) = _split(QuickCrypto.hmacSha512Hash(chainCode, data));
      // A left half >= n or a zero key has a chance of about 1 in 2^127:
      // BIP-32 says to skip to the next index, and real wallets never hit it.
      final child = (BigintUtils.fromBytes(left) + BigintUtils.fromBytes(key)) % n;
      key = BigintUtils.toBytes(child, length: 32);
      chainCode = right;
    }
    return key;
  }

  static (List<int>, List<int>) _split(List<int> hash) => (hash.sublist(0, 32), hash.sublist(32));

  static List<int> _u32(int value) => [value >> 24 & 0xff, value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff];

  /// Derives keys for every chain family from one recovery phrase.
  static Map<ChainFamily, ChainKey> deriveAll(String mnemonic) {
    final seed = seedFrom(mnemonic);
    return {for (final f in ChainFamily.values) f: derive(seed, f)};
  }

  /// Lowercases the phrase and collapses whitespace to single spaces.
  static String normalize(String mnemonic) => mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
}
