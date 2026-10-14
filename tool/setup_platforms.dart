// Generates the Flutter platform folders and patches them for Web3 wallets.
//
// The platform folders (android/, ios/, web/, macos/, windows/, linux/) are
// not committed. Run this once after cloning, from the repo root:
//
//   dart run tool/setup_platforms.dart
//
// It is safe to run again: every patch checks whether it was already applied.
// ignore_for_file: avoid_print
import 'dart:io';

const platforms = 'android,ios,web,macos,windows,linux';
const appName = 'Flutter Counter';

final app = Directory('flutter');

void main() {
  if (!File('flutter/pubspec.yaml').existsSync()) {
    fail('Run this from the repo root (the folder with flutter/ and server/).');
  }

  print('1. Generating platform folders with flutter create...');
  final result = Process.runSync(
    'flutter',
    [
      'create',
      '--project-name',
      'flutter_counter',
      '--org',
      'com.keepdeploying',
      '--platforms',
      platforms,
      '--empty',
      '.',
    ],
    workingDirectory: app.path,
    runInShell: true,
  );
  if (result.exitCode != 0) fail('flutter create failed:\n${result.stderr}');

  // flutter create also adds files this repo keeps elsewhere or ignores.
  for (final name in ['.gitignore', '.idea', 'flutter_counter.iml']) {
    final entity = File('${app.path}/$name');
    if (entity.existsSync()) entity.deleteSync();
    final dir = Directory('${app.path}/$name');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  print('2. Patching Android...');
  patchAndroid();
  print('3. Patching iOS...');
  patchIos();
  print('4. Patching macOS...');
  patchMacos();
  print('5. Patching window titles on Windows and Linux...');
  patchDesktopTitles();

  print('\nDone. Run the app with: cd flutter && flutter run');
}

void patchAndroid() {
  // The release build needs the INTERNET permission. Flutter only adds it to
  // the debug and profile manifests. allowBackup=false keeps the in-app
  // wallet's secure storage out of cloud backups.
  edit('android/app/src/main/AndroidManifest.xml', [
    Patch(
      marker: 'android.permission.INTERNET',
      find: '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
      replace:
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <uses-permission android:name="android.permission.INTERNET" />',
    ),
    // local_auth (fingerprint, face or PIN to unlock the in-app wallet).
    Patch(
      marker: 'android.permission.USE_BIOMETRIC',
      find: '<uses-permission android:name="android.permission.INTERNET" />',
      replace:
          '<uses-permission android:name="android.permission.INTERNET" />\n'
          '    <uses-permission android:name="android.permission.USE_BIOMETRIC" />',
    ),
    Patch(
      marker: 'android:allowBackup="false"',
      find: '<application\n',
      replace: '<application\n        android:allowBackup="false"\n',
    ),
    Patch(
      marker: 'android:label="$appName"',
      find: 'android:label="flutter_counter"',
      replace: 'android:label="$appName"',
    ),
  ]);

  // local_auth shows the system biometric prompt, which needs a
  // FragmentActivity and, on Android 8 and below, an AppCompat theme.
  edit('android/app/src/main/kotlin/com/keepdeploying/flutter_counter/MainActivity.kt', [
    Patch(marker: 'FlutterFragmentActivity', find: 'FlutterActivity', replace: 'FlutterFragmentActivity', all: true),
  ]);
  for (final folder in ['values', 'values-night']) {
    edit('android/app/src/main/res/$folder/styles.xml', [
      Patch(
        marker: 'name="LaunchTheme" parent="Theme.AppCompat.DayNight.NoActionBar"',
        find: folder == 'values'
            ? 'name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar"'
            : 'name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar"',
        replace: 'name="LaunchTheme" parent="Theme.AppCompat.DayNight.NoActionBar"',
      ),
    ]);
  }

  // Sign every build with the debug keystore committed in keys/, so an APK
  // from any machine installs over an earlier one. Testnet demo only.
  edit('android/app/build.gradle.kts', [
    // Release builds: the template signs them with the debug config.
    Patch(
      marker: 'signingConfigs.getByName("shared")',
      find: 'signingConfig = signingConfigs.getByName("debug")',
      replace: 'signingConfig = signingConfigs.getByName("shared")',
    ),
    // Define the shared config and use it for debug builds too.
    Patch(
      marker: 'create("shared")',
      find: '    buildTypes {',
      replace: '''    signingConfigs {
        create("shared") {
            storeFile = file("../../../keys/android-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("shared")
        }''',
    ),
  ]);
}

void patchIos() {
  // Face ID needs a reason shown to the user, or the app crashes when
  // local_auth asks. (Flutter's template already sets CFBundleDisplayName to
  // "Flutter Counter".)
  edit('ios/Runner/Info.plist', [
    Patch(
      marker: 'NSFaceIDUsageDescription',
      find: '\t<key>CFBundleDisplayName</key>',
      replace:
          '\t<key>NSFaceIDUsageDescription</key>\n'
          '\t<string>Face ID unlocks your Flutter Counter wallet.</string>\n'
          '\t<key>CFBundleDisplayName</key>',
    ),
  ]);
}

void patchMacos() {
  // macOS apps are sandboxed. The release build needs explicit permission to
  // make network requests to RPC endpoints.
  edit('macos/Runner/Release.entitlements', [
    Patch(
      marker: 'com.apple.security.network.client',
      find: '<key>com.apple.security.app-sandbox</key>\n\t<true/>',
      replace:
          '<key>com.apple.security.app-sandbox</key>\n\t<true/>\n'
          '\t<key>com.apple.security.network.client</key>\n\t<true/>',
    ),
  ]);
  edit('macos/Runner/DebugProfile.entitlements', [
    Patch(
      marker: 'com.apple.security.network.client',
      find: '<key>com.apple.security.app-sandbox</key>\n\t<true/>',
      replace:
          '<key>com.apple.security.app-sandbox</key>\n\t<true/>\n'
          '\t<key>com.apple.security.network.client</key>\n\t<true/>',
    ),
  ]);
}

void patchDesktopTitles() {
  edit('windows/runner/main.cpp', [Patch(marker: 'L"$appName"', find: 'L"flutter_counter"', replace: 'L"$appName"')]);
  edit('linux/runner/my_application.cc', [
    Patch(marker: '"$appName"', find: '"flutter_counter"', replace: '"$appName"', all: true),
  ]);
}

class Patch {
  const Patch({
    required this.marker,
    required this.find,
    required this.replace,
    this.findAlternatives = const [],
    this.all = false,
  });

  /// Text that is only present once the patch is applied.
  final String marker;
  final String find;
  final String replace;
  final List<String> findAlternatives;
  final bool all;
}

void edit(String relativePath, List<Patch> patches) {
  final file = File('${app.path}/$relativePath');
  if (!file.existsSync()) fail('Missing ${file.path}. Did flutter create run?');
  final original = file.readAsStringSync();
  var text = original;
  for (final p in patches) {
    if (text.contains(p.marker)) continue;
    final target = [p.find, ...p.findAlternatives].firstWhere(
      text.contains,
      orElse: () => fail(
        'Could not patch $relativePath: expected to find\n${p.find}\n'
        'The Flutter template may have changed. Apply the change by hand.',
      ),
    );
    text = p.all ? text.replaceAll(target, p.replace) : text.replaceFirst(target, p.replace);
  }
  if (text == original) {
    print('   already patched $relativePath');
    return;
  }
  file.writeAsStringSync(text);
  print('   patched $relativePath');
}

Never fail(String message) {
  stderr.writeln('\nError: $message');
  exit(1);
}
