import 'dart:io';

import 'package:flutter/widgets.dart';

import '../installed/installed_wallet.dart';
import 'reown_wallet.dart';

/// AppKit for Flutter supports Android and iOS only.
InstalledWallet? createReownWallet(GlobalKey<NavigatorState> navigatorKey, String projectId) =>
    Platform.isAndroid || Platform.isIOS ? ReownWallet(navigatorKey: navigatorKey, projectId: projectId) : null;
