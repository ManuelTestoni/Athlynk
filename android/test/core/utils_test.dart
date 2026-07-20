import 'package:athlynk/core/cache/memory_cache.dart';
import 'package:athlynk/core/l10n/formatters.dart';
import 'package:athlynk/core/push/push_bridge.dart';
import 'package:athlynk/core/utils/rpe_rir.dart';
import 'package:athlynk/core/utils/weekday.dart';
import 'package:athlynk/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MemoryCache', () {
    test('returns a value inside the 5-minute window', () {
      var now = DateTime(2026, 7, 20, 10);
      final cache = MemoryCache(clock: () => now);

      cache.set(CacheKeys.dashboardSummary, 'payload');
      now = now.add(const Duration(minutes: 4, seconds: 59));

      expect(cache.get<String>(CacheKeys.dashboardSummary), 'payload');
    });

    test('drops the entry once it goes stale', () {
      var now = DateTime(2026, 7, 20, 10);
      final cache = MemoryCache(clock: () => now);

      cache.set(CacheKeys.dashboardWorkouts, 'payload');
      now = now.add(const Duration(minutes: 5, seconds: 1));

      expect(cache.get<String>(CacheKeys.dashboardWorkouts), isNull);
    });

    test('type mismatch never throws, it just misses', () {
      final cache = MemoryCache();
      cache.set(CacheKeys.dashboardLayout, 'a string');

      expect(cache.get<int>(CacheKeys.dashboardLayout), isNull);
    });

    test('invalidateAll clears everything (logout path)', () {
      final cache = MemoryCache()
        ..set(CacheKeys.dashboardSummary, 1)
        ..set(CacheKeys.coachDashboard, 2);

      cache.invalidateAll();

      expect(cache.get<int>(CacheKeys.dashboardSummary), isNull);
      expect(cache.get<int>(CacheKeys.coachDashboard), isNull);
    });
  });

  group('RPE ↔ RIR', () {
    test('converts with the RPE ≈ 10 − RIR rule', () {
      expect(rpeFromRir(2), 8);
      expect(rirFromRpe(8), 2);
    });

    test('clamps to the meaningful 0–10 band', () {
      expect(rpeFromRir(15), 0);
      expect(rirFromRpe(-3), 10);
    });
  });

  group('DietWeekday', () {
    test('maps backend codes to Italian labels', () {
      expect(DietWeekday.fromCode('MONDAY'), DietWeekday.monday);
      expect(DietWeekday.monday.long, 'Lunedì');
      expect(DietWeekday.sunday.short, 'DOM');
      expect(DietWeekday.fromCode('nope'), isNull);
      expect(DietWeekday.fromCode(null), isNull);
    });

    test('weeks run Monday→Sunday', () {
      // 2026-07-20 is a Monday.
      final monday = DateTime(2026, 7, 20);
      expect(DietWeekday.fromDate(monday), DietWeekday.monday);
      expect(DietWeekday.friday.dateInWeekOf(monday), DateTime(2026, 7, 24));
      // Same week resolved from a mid-week reference.
      final thursday = DateTime(2026, 7, 23);
      expect(DietWeekday.monday.dateInWeekOf(thursday), DateTime(2026, 7, 20));
    });
  });

  group('Formatters', () {
    setUpAll(() async {
      await Formatters.init();
    });

    test('decimal uses the Italian comma and trims zeros', () {
      expect(Formatters.decimal(82.5), '82,5');
      expect(Formatters.decimal(82.0), '82');
      expect(Formatters.decimal(0.0), '0');
    });

    test('parseDecimal accepts both comma and dot input', () {
      expect(Formatters.parseDecimal('82,5'), 82.5);
      expect(Formatters.parseDecimal('82.5'), 82.5);
      expect(Formatters.parseDecimal(' 7 '), 7);
      expect(Formatters.parseDecimal(''), isNull);
      expect(Formatters.parseDecimal('abc'), isNull);
    });

    test('parseDate handles ISO datetimes and bare dates', () {
      expect(Formatters.parseDate('2026-07-20'), DateTime(2026, 7, 20));
      expect(Formatters.parseDate('2026-07-20T08:30:00Z')?.isUtc, isTrue);
      expect(Formatters.parseDate(null), isNull);
      expect(Formatters.parseDate(''), isNull);
    });

    test('it_IT date output', () {
      final d = DateTime(2026, 7, 20);
      expect(Formatters.mediumDate(d), '20 lug 2026');
      expect(Formatters.longDate(d), '20 luglio 2026');
      expect(Formatters.shortDate(d), '20/07/2026');
    });

    test('relative labels stay Italian and short', () {
      final now = DateTime.now();
      expect(Formatters.relative(now), 'adesso');
      expect(Formatters.relative(now.subtract(const Duration(minutes: 5))),
          '5 min fa');
      expect(
          Formatters.relative(now.subtract(const Duration(hours: 3))), '3 h fa');
    });

    test('price renders the euro symbol', () {
      expect(Formatters.price(49.9), '€ 49,90');
    });
  });

  group('brand theme', () {
    test('hex round-trips and rejects malformed input', () {
      expect(colorFromHexString('#1E3A5F'), const Color(0xFF1E3A5F));
      expect(colorFromHexString('1E3A5F'), isNull); // missing '#'
      expect(colorFromHexString('#XYZ'), isNull);
      expect(colorFromHexString(null), isNull);
      expect(const Color(0xFF1E3A5F).hexString, '#1E3A5F');
    });

    test('load falls back to the Athlynk defaults', () {
      BrandTheme.load('#AA0000', null);
      expect(Palette.magenta, const Color(0xFFAA0000));
      expect(Palette.cyan, Palette.defaultAccent);

      BrandTheme.load(null, null);
      expect(Palette.magenta, Palette.defaultPrimary);
      expect(Palette.cyan, Palette.defaultAccent);
    });

    test('apply bumps themeVersion so the tree remounts', () {
      final before = BrandTheme.themeVersion.value;
      BrandTheme.apply(primary: const Color(0xFF112233));
      expect(BrandTheme.themeVersion.value, before + 1);
      BrandTheme.reset();
    });
  });

  group('PushBridge', () {
    test('filters events by type', () async {
      final bridge = PushBridge();
      final seen = <String>[];
      final sub = bridge
          .onTypes({RemoteChangeType.workoutAssigned}).listen(seen.add);

      bridge.emit(RemoteChangeType.workoutAssigned);
      bridge.emit(RemoteChangeType.message);
      bridge.emit('workout_assigned'); // case-insensitive
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['WORKOUT_ASSIGNED', 'WORKOUT_ASSIGNED']);
      await sub.cancel();
      bridge.dispose();
    });

    test('an empty filter set means "everything"', () async {
      final bridge = PushBridge();
      final seen = <String>[];
      final sub = bridge.onTypes(const {}).listen(seen.add);

      bridge.emit(RemoteChangeType.message);
      bridge.emit(RemoteChangeType.checkReviewed);
      await Future<void>.delayed(Duration.zero);

      expect(seen, ['MESSAGE', 'CHECK_REVIEWED']);
      await sub.cancel();
      bridge.dispose();
    });
  });
}
