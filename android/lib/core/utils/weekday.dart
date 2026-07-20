/// Canonical IT weekday mapping — port of iOS `DietWeekday`
/// (backend codes `MONDAY…SUNDAY` ↔ `Lunedì…Domenica` / `LUN…DOM`).
enum DietWeekday {
  monday('MONDAY', 'Lunedì', 'LUN'),
  tuesday('TUESDAY', 'Martedì', 'MAR'),
  wednesday('WEDNESDAY', 'Mercoledì', 'MER'),
  thursday('THURSDAY', 'Giovedì', 'GIO'),
  friday('FRIDAY', 'Venerdì', 'VEN'),
  saturday('SATURDAY', 'Sabato', 'SAB'),
  sunday('SUNDAY', 'Domenica', 'DOM');

  const DietWeekday(this.code, this.long, this.short);

  /// Backend code (`MONDAY`…).
  final String code;
  final String long;
  final String short;

  static DietWeekday? fromCode(String? code) {
    if (code == null) return null;
    final upper = code.toUpperCase();
    for (final d in values) {
      if (d.code == upper) return d;
    }
    return null;
  }

  /// 1 = Monday … 7 = Sunday (DateTime.weekday convention).
  int get isoWeekday => index + 1;

  static DietWeekday fromDate(DateTime date) => values[date.weekday - 1];

  /// The date of this weekday in the week containing [reference]
  /// (weeks run Monday→Sunday).
  DateTime dateInWeekOf(DateTime reference) {
    final monday =
        DateTime(reference.year, reference.month, reference.day)
            .subtract(Duration(days: reference.weekday - 1));
    return monday.add(Duration(days: index));
  }
}
