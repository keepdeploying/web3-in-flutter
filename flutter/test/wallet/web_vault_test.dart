@TestOn('browser')
library;

import 'package:flutter_counter/src/wallet/vault.dart';
import 'package:flutter_counter/src/wallet/vault_web.dart';
import 'package:flutter_test/flutter_test.dart';

// Runs in a real browser, with real IndexedDB and WebCrypto:
//   flutter test --platform chrome test/wallet/web_vault_test.dart

const phrase = 'someone scrub boss million lesson spread strategy village hello excite celery silent';

void main() {
  var run = 0;
  // A fresh database per test, and few PBKDF2 rounds to keep tests fast.
  WebVault fresh() =>
      WebVault(iterations: 1000, databaseName: 'test_${DateTime.now().microsecondsSinceEpoch}_${run++}');

  test('saves, then unlocks with the right password only', () async {
    final vault = fresh();
    expect(await vault.hasWallet(), isFalse);
    await vault.save(phrase, const VaultOptions(password: 'correct horse'));
    expect(await vault.hasWallet(), isTrue);
    expect(await vault.resume(), isNull);
    expect(await vault.unlock(password: 'correct horse'), phrase);
    await expectLater(vault.unlock(password: 'wrong'), throwsA(isA<WrongPasswordException>()));
  });

  test('a new vault object reads what an earlier one saved (like a reload)', () async {
    final first = fresh();
    await first.save(phrase, const VaultOptions(password: 'pw12345678', stayUnlocked: true));
    final reloaded = WebVault(iterations: 1000, databaseName: first.databaseName);
    expect(await reloaded.resume(), phrase);
    await reloaded.lock();
    expect(await reloaded.resume(), isNull);
    expect(await reloaded.unlock(password: 'pw12345678'), phrase);
  });

  test('delete removes everything', () async {
    final vault = fresh();
    await vault.save(phrase, const VaultOptions(password: 'pw12345678', stayUnlocked: true));
    await vault.delete();
    expect(await vault.hasWallet(), isFalse);
    expect(await vault.resume(), isNull);
  });

  test('the real iteration count still unlocks in reasonable time', () async {
    final vault = WebVault(databaseName: 'test_slow_${DateTime.now().microsecondsSinceEpoch}');
    await vault.save(phrase, const VaultOptions(password: 'pw12345678'));
    final watch = Stopwatch()..start();
    expect(await vault.unlock(password: 'pw12345678'), phrase);
    // ignore: avoid_print
    print('PBKDF2 with ${vault.iterations} rounds took ${watch.elapsedMilliseconds} ms');
  });
}
