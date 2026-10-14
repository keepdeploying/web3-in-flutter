import 'dart:convert';

/// Just enough protobuf to build a Cosmos transaction.
///
/// Each field is a key (field number and wire type) then the value: a
/// varint for numbers, or a varint length and the bytes for strings,
/// bytes and nested messages. Fields with default values (0, empty) are
/// left out, as protobuf encoders do.
abstract final class Proto {
  static List<int> message(List<List<int>> fields) => [for (final f in fields) ...f];

  static List<int> uint(int field, int value) => value == 0 ? const [] : [..._varint(field << 3), ..._varint(value)];

  static List<int> bytes(int field, List<int> value) => [
    ..._varint(field << 3 | 2),
    ..._varint(value.length),
    ...value,
  ];

  static List<int> string(int field, String value) => value.isEmpty ? const [] : bytes(field, utf8.encode(value));

  /// The SignDoc that SIGN_MODE_DIRECT signs: body, auth info, chain ID
  /// and account number. The signature is over sha256 of these bytes.
  static List<int> signDoc({
    required List<int> body,
    required List<int> authInfo,
    required String chainId,
    required int accountNumber,
  }) => message([bytes(1, body), bytes(2, authInfo), string(3, chainId), uint(4, accountNumber)]);

  /// google.protobuf.Any: a type URL and the encoded message.
  static List<int> any(String typeUrl, List<int> value) => message([string(1, typeUrl), bytes(2, value)]);

  static List<int> _varint(int value) {
    final out = <int>[];
    do {
      var byte = value & 0x7f;
      value >>= 7;
      if (value != 0) byte |= 0x80;
      out.add(byte);
    } while (value != 0);
    return out;
  }
}
