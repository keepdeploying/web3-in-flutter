import 'package:flutter_counter_server/flutter_counter_server.dart';
import 'package:test/test.dart';

void main() {
  test('health reports the backend mode', () {
    expect(health(mode: 'local'), containsPair('mode', 'local'));
  });
}
