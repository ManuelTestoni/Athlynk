import 'package:flutter/material.dart';

import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';

/// Single meal — port of iOS `MealDetailView`: total kcal + P/C/F columns,
/// per-food breakdown.
class MealDetailView extends StatelessWidget {
  const MealDetailView({super.key, required this.meal});

  final MealDto meal;

  @override
  Widget build(BuildContext context) {
    final protein = meal.items.fold<double>(0, (s, i) => s + i.protein);
    final carbs = meal.items.fold<double>(0, (s, i) => s + i.carbs);
    final fat = meal.items.fold<double>(0, (s, i) => s + i.fat);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        children: [
          ScreenHeader(
            eyebrow: meal.timeOfDay ?? 'Pasto',
            title: meal.name,
            titleSize: 32,
          ),
          VoltPanel(
            child: Row(
              children: [
                _col('${meal.kcal.toInt()}', 'kcal', Palette.amber),
                _col('${protein.toInt()}g', 'proteine', Palette.magenta),
                _col('${carbs.toInt()}g', 'carboidrati', Palette.cyan),
                _col('${fat.toInt()}g', 'grassi', Palette.lime),
              ],
            ),
          ),
          const SectionHeader(title: 'Alimenti', eyebrow: 'Composizione'),
          for (final item in meal.items)
            VoltPanel(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name ?? 'Alimento',
                            style: Typo.body(14.5, FontWeight.w600)),
                        Text(
                          '${Formatters.decimal(item.quantityG)} g · P ${item.protein.toInt()} · C ${item.carbs.toInt()} · F ${item.fat.toInt()}',
                          style: Typo.mono(
                              10, FontWeight.w600, Palette.textMid),
                        ),
                      ],
                    ),
                  ),
                  Text('${item.kcal.toInt()} kcal',
                      style: Typo.mono(12, FontWeight.w700, Palette.amber)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _col(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: Typo.poster(22)),
          Text(label.toUpperCase(),
              style: Typo.mono(7.5, FontWeight.w700, color)
                  .copyWith(letterSpacing: 1)),
        ],
      ),
    );
  }
}
