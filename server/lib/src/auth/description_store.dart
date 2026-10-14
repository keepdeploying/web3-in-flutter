import 'session_tokens.dart';

/// One short text per signed-in account: the "protected endpoint" of the
/// demo. Only a valid session can write it, and everyone can read the list.
class Description {
  const Description({required this.family, required this.address, required this.text, required this.updatedAt});

  final String family;
  final String address;
  final String text;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
    'family': family,
    'address': address,
    'text': text,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory Description.fromJson(Map<String, dynamic> json) => Description(
    family: json['family'] as String,
    address: json['address'] as String,
    text: json['text'] as String,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );
}

/// In memory, like the nonces: enough for a demo.
class DescriptionStore {
  DescriptionStore({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  static const maxLength = 140;

  final DateTime Function() _now;
  final _byAccount = <String, Description>{};

  Description set(Session session, String text) {
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('Write something first.');
    if (clean.length > maxLength) throw ArgumentError('Keep it under $maxLength characters.');
    return _byAccount[session.accountKey] = Description(
      family: session.family.name,
      address: session.address,
      text: clean,
      updatedAt: _now().toUtc(),
    );
  }

  Description? of(Session session) => _byAccount[session.accountKey];

  /// Newest first.
  List<Description> list() => _byAccount.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
}
