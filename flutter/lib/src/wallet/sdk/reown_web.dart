import 'package:flutter/widgets.dart';

import '../installed/installed_wallet.dart';

/// AppKit for Flutter has no web support. On the web, wallets are found
/// directly (option 2).
InstalledWallet? createReownWallet(GlobalKey<NavigatorState> navigatorKey, String projectId) => null;
