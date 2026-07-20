import 'package:flutter/material.dart';

import '../theme.dart';

/// Modal sheet idiom shared app-wide — the Android counterpart of iOS
/// `.sheet { NavigationStack { … } }`: rounded top, near-full height, its own
/// nested Navigator so content can push details and pop back within the
/// sheet.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double heightFactor = 0.94,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Palette.textHi.withValues(alpha: 0.3),
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: heightFactor,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: Container(
            color: Palette.void0,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Palette.void2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (settings) => MaterialPageRoute(
                      settings: settings,
                      builder: builder,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
