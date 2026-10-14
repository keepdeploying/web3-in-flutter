import 'dart:convert';

import 'package:blockchain_utils/blockchain_utils.dart';

/// EIP-55: the address with letters in upper case wherever that nibble of
/// keccak256(the lower-case address) is 8 or more. Wallets often return
/// lower case; the mixed case lets people and apps catch typos.
String toChecksumAddress(String address) {
  final hex = address.toLowerCase().replaceFirst('0x', '');
  final hash = BytesUtils.toHexString(QuickCrypto.keccack256Hash(utf8.encode(hex)));
  return '0x${[for (var i = 0; i < hex.length; i++) int.parse(hash[i], radix: 16) >= 8 ? hex[i].toUpperCase() : hex[i]].join()}';
}
