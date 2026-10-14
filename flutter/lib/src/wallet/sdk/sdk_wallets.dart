import 'package:flutter/widgets.dart';

import '../installed/installed_wallet.dart';
import 'near_connect_wallet.dart';
import 'reown_native.dart' if (dart.library.js_interop) 'reown_web.dart' as reown;

/// The Reown project ID for this demo. It is public on purpose, like the
/// testnet keys: anyone can read it from the app anyway. Reown only accepts
/// it from the app IDs allowlisted in its dashboard
/// (com.keepdeploying.flutter_counter, com.keepdeploying.flutterCounter).
/// For your own app, create a project at https://dashboard.reown.com.
const reownProjectId = 'c2882295d4bcc919bfb58e4e555cecbd';

/// The wallets reached through an SDK: Reown AppKit on Android and iOS, and
/// near_wallet_connect's NEAR wallets everywhere.
List<InstalledWallet> sdkWallets(GlobalKey<NavigatorState> navigatorKey) => [
  ?reown.createReownWallet(navigatorKey, reownProjectId),
  ...NearConnectWallet.all(),
];
