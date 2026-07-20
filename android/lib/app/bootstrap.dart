import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/formatters.dart';
import '../core/providers.dart';
import '../core/utils/frame_stats.dart';
import 'athlynk_app.dart';

/// Common boot path for both entry points.
Future<void> runAthlynk(FlavorConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  FrameStats.start();

  // Edge-to-edge with dark status-bar icons on the light theme.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp]);

  await Formatters.init();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        flavorProvider.overrideWithValue(config.flavor),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: AthlynkApp(config: config),
    ),
  );
}
