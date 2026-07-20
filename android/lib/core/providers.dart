import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/session_controller.dart';
import 'auth/token_storage.dart';
import 'cache/memory_cache.dart';
import 'network/api_client.dart';
import 'push/push_bridge.dart';

/// App flavor — which of the two apps this binary is (set by the entry point,
/// mirrors the two iOS targets).
enum AppFlavor {
  athlete(
    role: 'CLIENT',
    bundleId: 'it.athlynk.athlynk',
    deepLinkScheme: 'athlynk',
  ),
  coach(
    role: 'COACH',
    bundleId: 'it.athlynk.athlynk.coach',
    deepLinkScheme: 'athlynkcoach',
  );

  const AppFlavor({
    required this.role,
    required this.bundleId,
    required this.deepLinkScheme,
  });

  /// Login role filter ("CLIENT" | "COACH").
  final String role;
  final String bundleId;
  final String deepLinkScheme;
}

/// Overridden in each entry point.
final flavorProvider = Provider<AppFlavor>((ref) => AppFlavor.athlete);

/// Overridden at bootstrap with the real instance.
final prefsProvider = Provider<SharedPreferences>(
    (ref) => throw UnimplementedError('override at boot'));

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final memoryCacheProvider = Provider<MemoryCache>((ref) => MemoryCache());

final pushBridgeProvider = Provider<PushBridge>((ref) {
  final bridge = PushBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
