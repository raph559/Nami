import 'dart:io';

import 'package:flutter/foundation.dart';

/// Forces the desktop (true) or touch (false) layout in tests.
@visibleForTesting
bool? debugDesktopOverride;

/// Mouse and keyboard platforms get the desktop layout, whatever the window width.
bool get isDesktop => debugDesktopOverride ?? (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
