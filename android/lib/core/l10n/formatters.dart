import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// it_IT date/number formatting (iOS uses `Locale(identifier: "it_IT")`
/// everywhere). Call [Formatters.init] once at bootstrap.
class Formatters {
  Formatters._();

  static const locale = 'it_IT';

  static Future<void> init() => initializeDateFormatting(locale);

  /// "12 gen 2026"
  static String mediumDate(DateTime d) =>
      DateFormat('d MMM yyyy', locale).format(d);

  /// "12 gennaio 2026"
  static String longDate(DateTime d) =>
      DateFormat('d MMMM yyyy', locale).format(d);

  /// "gen 2026" — month group headers.
  static String monthYear(DateTime d) =>
      DateFormat('MMMM yyyy', locale).format(d);

  /// "lunedì 12 gennaio"
  static String weekdayLongDate(DateTime d) =>
      DateFormat('EEEE d MMMM', locale).format(d);

  /// "14:30"
  static String time(DateTime d) => DateFormat('HH:mm', locale).format(d);

  /// "12/01/2026"
  static String shortDate(DateTime d) =>
      DateFormat('dd/MM/yyyy', locale).format(d);

  /// Relative label for feeds: "adesso", "5 min fa", "2 h fa", else date.
  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'adesso';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min fa';
    if (diff.inHours < 24) return '${diff.inHours} h fa';
    if (diff.inDays < 7) return '${diff.inDays} g fa';
    return mediumDate(d);
  }

  /// Decimal with comma ("82,5"), trimming trailing zeros.
  static String decimal(num v, {int maxDecimals = 1}) {
    var s = v.toStringAsFixed(maxDecimals);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return s.replaceAll('.', ',');
  }

  /// "€ 49,90"
  static String price(num v, {String currency = 'EUR'}) {
    final symbol = currency.toUpperCase() == 'EUR' ? '€' : currency;
    return '$symbol ${NumberFormat('#,##0.00', locale).format(v)}';
  }

  /// Parses a comma-tolerant decimal typed by the user ("82,5" or "82.5").
  static double? parseDecimal(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  /// Parses backend dates: full ISO-8601 or bare `yyyy-MM-dd`.
  static DateTime? parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
