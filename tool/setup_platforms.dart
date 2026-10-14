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
const appShortName = 'Counter';
const appDescription = 'Read, sign in and write on EVM, Solana, Sui, Cosmos and NEAR testnets from one Flutter app.';

/// Brand indigo (the Material 3 seed color), also the icon background.
const brandColor = '#5B5BD6';

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
  print('6. Patching the web page and manifest...');
  patchWeb();
  print('7. Setting the Linux window icon...');
  patchLinuxIcon();

  print('8. Generating launcher icons...');
  generateLauncherIcons();

  print('9. Installing the small web favicon...');
  installFavicon();

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
    // Wallet apps answer by opening fluttercounter://wallet/..., and
    // app_links reads it. Flutter's own deep linking would try to open
    // that as a route, so it is turned off.
    Patch(
      marker: 'android:scheme="fluttercounter"',
      find: '''            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>''',
      replace: '''            <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="fluttercounter" android:host="wallet" />
            </intent-filter>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>''',
    ),
    // Since Android 11, an app only sees the apps it says it looks for:
    // the wallets the Sign in screen finds by their link schemes.
    Patch(
      marker: 'android:scheme="solana-wallet"',
      find: '    <queries>\n',
      replace: '''    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="solana-wallet" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="phantom" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="solflare" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
''',
    ),
    // Every fluttercounter:// link, not only wallet/: near_wallet_connect
    // answers on fluttercounter://callback.
    Patch(
      marker: '<data android:scheme="fluttercounter" />',
      find: '<data android:scheme="fluttercounter" android:host="wallet" />',
      replace: '<data android:scheme="fluttercounter" />',
    ),
    // Reown AppKit marks the wallets that are installed. It checks these
    // apps by package name.
    Patch(
      marker: 'android:name="io.metamask"',
      find: '    <queries>\n',
      replace: '''    <queries>
        <package android:name="io.metamask" />
        <package android:name="com.wallet.crypto.trustapp" />
        <package android:name="me.rainbow" />
        <package android:name="org.toshi" />
        <package android:name="io.zerion.android" />
        <package android:name="app.phantom" />
        <package android:name="com.solflare.mobile" />
''',
    ),
    // The Mobile Wallet Adapter talks to the wallet over a WebSocket on
    // localhost, which is plain ws://. Android blocks unencrypted traffic
    // unless the app allows it, so allow it for localhost only.
    Patch(
      marker: 'android:networkSecurityConfig',
      find: '<application\n',
      replace: '<application\n        android:networkSecurityConfig="@xml/network_security_config"\n',
    ),
  ]);
  final securityConfig = File('${app.path}/android/app/src/main/res/xml/network_security_config.xml');
  if (!securityConfig.existsSync()) {
    securityConfig
      ..createSync(recursive: true)
      ..writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">localhost</domain>
        <domain includeSubdomains="false">127.0.0.1</domain>
    </domain-config>
</network-security-config>
''');
    print('   wrote android/app/src/main/res/xml/network_security_config.xml');
  }

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

  // Reown AppKit pulls in coinbase_wallet_sdk, which still compiles against
  // Android API 31 (its own dependencies need 34 or later) and points at a
  // ProGuard file it doesn't ship. Fix both for every build.
  edit('android/build.gradle.kts', [
    Patch(
      marker: 'compileSdkVersion(36)',
      find: 'subprojects {\n    project.evaluationDependsOn(":app")',
      replace: '''// Some plugins still compile against old Android APIs that their own
// dependencies no longer support. Build them all against API 36.
// coinbase_wallet_sdk also names a consumer-rules.pro it doesn't ship,
// which breaks release builds, so drop that reference.
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.compileSdkVersion(36)
        if (project.name == "coinbase_wallet_sdk") {
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)
                ?.defaultConfig?.consumerProguardFiles?.clear()
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")''',
    ),
  ]);

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
    // Wallet apps answer by opening fluttercounter://wallet/..., which
    // app_links reads; Flutter's own deep linking stays off. The queried
    // schemes are the wallets the Sign in screen looks for.
    Patch(
      marker: '<string>fluttercounter</string>',
      find: '\t<key>CFBundleDisplayName</key>',
      replace:
          '\t<key>CFBundleURLTypes</key>\n'
          '\t<array>\n'
          '\t\t<dict>\n'
          '\t\t\t<key>CFBundleURLName</key>\n'
          '\t\t\t<string>com.keepdeploying.flutterCounter.wallet</string>\n'
          '\t\t\t<key>CFBundleURLSchemes</key>\n'
          '\t\t\t<array>\n'
          '\t\t\t\t<string>fluttercounter</string>\n'
          '\t\t\t</array>\n'
          '\t\t</dict>\n'
          '\t</array>\n'
          '\t<key>FlutterDeepLinkingEnabled</key>\n'
          '\t<false/>\n'
          '\t<key>LSApplicationQueriesSchemes</key>\n'
          '\t<array>\n'
          '\t\t<string>phantom</string>\n'
          '\t\t<string>solflare</string>\n'
          '\t\t<string>keplrwallet</string>\n'
          '\t</array>\n'
          '\t<key>CFBundleDisplayName</key>',
    ),
    // Reown AppKit checks which wallets are installed by their schemes.
    Patch(
      marker: '<string>metamask</string>',
      find: '\t\t<string>keplrwallet</string>\n',
      replace:
          '\t\t<string>keplrwallet</string>\n'
          '\t\t<string>metamask</string>\n'
          '\t\t<string>trust</string>\n'
          '\t\t<string>rainbow</string>\n'
          '\t\t<string>cbwallet</string>\n'
          '\t\t<string>zerion</string>\n'
          '\t\t<string>wc</string>\n',
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

void patchWeb() {
  // The template names the app after the package and uses Flutter blue.
  edit('web/index.html', [
    Patch(
      marker: 'content="$appDescription"',
      find: 'content="A new Flutter project."',
      replace: 'content="$appDescription"',
    ),
    Patch(
      marker: 'name="theme-color"',
      find: '<meta name="description"',
      replace: '<meta name="theme-color" content="$brandColor">\n  <meta name="description"',
    ),
    Patch(marker: 'content="$appName"', find: 'content="flutter_counter"', replace: 'content="$appName"'),
    Patch(
      marker: '<title>$appName</title>',
      find: '<title>flutter_counter</title>',
      replace: '<title>$appName</title>',
    ),
  ]);
  edit('web/manifest.json', [
    Patch(marker: '"name": "$appName"', find: '"name": "flutter_counter"', replace: '"name": "$appName"'),
    Patch(
      marker: '"short_name": "$appShortName"',
      find: '"short_name": "flutter_counter"',
      replace: '"short_name": "$appShortName"',
    ),
    Patch(
      marker: '"background_color": "$brandColor"',
      find: '"background_color": "#0175C2"',
      replace: '"background_color": "$brandColor"',
    ),
    Patch(
      marker: '"theme_color": "$brandColor"',
      find: '"theme_color": "#0175C2"',
      replace: '"theme_color": "$brandColor"',
    ),
    Patch(
      marker: '"description": "$appDescription"',
      find: '"description": "A new Flutter project."',
      replace: '"description": "$appDescription"',
    ),
  ]);
}

void patchLinuxIcon() {
  // flutter_launcher_icons does not do Linux. The icon ships as a Flutter
  // asset (see pubspec.yaml), so it sits at a fixed place next to the
  // executable: <bundle>/data/flutter_assets/assets/icon/icon.png.
  edit('linux/runner/my_application.cc', [
    Patch(
      marker: 'gtk_window_set_icon_from_file',
      find: '  gtk_window_set_default_size(window, 1280, 720);',
      replace: '''  // Window icon, found relative to the executable so it works from any folder.
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path = g_build_filename(
        exe_dir, "data", "flutter_assets", "assets", "icon", "icon.png", nullptr);
    gtk_window_set_icon_from_file(window, icon_path, nullptr);
  }

  gtk_window_set_default_size(window, 1280, 720);''',
    ),
  ]);
}

void generateLauncherIcons() {
  // Reads the flutter_launcher_icons section of flutter/pubspec.yaml and the
  // source images in flutter/assets/icon/. It rewrites the icon files in every
  // platform folder, so running it again gives the same result.
  final result = Process.runSync(
    'dart',
    ['run', 'flutter_launcher_icons'],
    workingDirectory: app.path,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    fail(
      'flutter_launcher_icons failed (exit code ${result.exitCode}):\n'
      '${result.stdout}\n${result.stderr}\n'
      'Try it by hand: cd flutter && dart run flutter_launcher_icons',
    );
  }
  print('   generated icons for Android, iOS, web, Windows and macOS');
}

void installFavicon() {
  // The launcher icons step shrinks the full icon to a 16 px favicon, where the
  // ring and dots are unreadable. Overwrite it with the bold "+1" version
  // (rendered from assets/icon/icon-small.svg).
  final source = File('${app.path}/assets/icon/favicon.png');
  if (!source.existsSync()) fail('Missing ${source.path}.');
  source.copySync('${app.path}/web/favicon.png');
  print('   copied assets/icon/favicon.png to web/favicon.png');
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
