import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame-time reporter for diagnosing jank on device/emulator.
///
/// Off unless the app is launched with `--dart-define=PERF_HUD=true`, and
/// never runs in release. Every [_window] it logs the p50/p95/worst of the
/// two phases the engine reports separately:
///
///  * **build** — the UI thread: widget rebuild + layout + paint recording.
///    High here means too much Dart work per frame (rebuilding subtrees,
///    expensive `CustomPainter.paint`).
///  * **raster** — the GPU thread: turning the recorded picture into pixels.
///    High here means too much drawing (blurs, shadows, large repaints,
///    fill-rate) — the emulator's translated GPU punishes this hardest.
///
/// Budget is 16.7 ms per phase at 60 Hz. Read the two numbers separately:
/// they point at completely different fixes.
class FrameStats {
  FrameStats._();

  static const enabled =
      bool.fromEnvironment('PERF_HUD') && !bool.fromEnvironment('dart.vm.product');

  static const _window = Duration(seconds: 3);

  static final List<double> _build = [];
  static final List<double> _raster = [];
  static DateTime _last = DateTime.now();

  static void start() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _emit('on — reporting every ${_window.inSeconds}s');
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds / 1000);
      _raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
    final now = DateTime.now();
    if (now.difference(_last) < _window) return;
    _last = now;
    if (_build.isEmpty) return;

    final frames = _build.length;
    final janky = List.generate(frames, (i) => i)
        .where((i) => _build[i] > 16.7 || _raster[i] > 16.7)
        .length;

    _emit('frames=$frames janky=$janky (${(janky * 100 / frames).round()}%)  '
        'build ${_fmt(_build)}  raster ${_fmt(_raster)}');
    _build.clear();
    _raster.clear();
  }

  // `debugPrint`, not `dart:developer` — profile builds surface stdout in
  // `flutter run`, but not the logging stream.
  static void _emit(String msg) => debugPrint('[perf] $msg');

  static String _fmt(List<double> xs) {
    final s = [...xs]..sort();
    String ms(double v) => v.toStringAsFixed(1);
    return 'p50=${ms(s[s.length ~/ 2])} '
        'p95=${ms(s[(s.length * 0.95).floor().clamp(0, s.length - 1)])} '
        'max=${ms(s.last)}ms';
  }
}
