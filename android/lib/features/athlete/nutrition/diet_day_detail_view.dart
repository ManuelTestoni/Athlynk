import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/weekday.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/theme.dart';
import 'meal_detail_view.dart';

/// One FOOD-plan day, paged prev/next with chevrons + swipe — port of iOS
/// `DietDayDetailView` (edge-swipe-back preserved by requiring the drag to
/// start away from the left edge).
class DietDayDetailView extends StatefulWidget {
  const DietDayDetailView({
    super.key,
    required this.plan,
    required this.initialDay,
  });

  final NutritionPlanDto plan;
  final DietDayDto initialDay;

  @override
  State<DietDayDetailView> createState() => _DietDayDetailViewState();
}

class _DietDayDetailViewState extends State<DietDayDetailView> {
  late int _index = widget.plan.days.indexWhere(
      (d) => d.id == widget.initialDay.id);
  int _direction = 1;

  List<DietDayDto> get _days => widget.plan.days;

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _days.length) return;
    Haptics.tap();
    setState(() {
      _direction = delta;
      _index = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_index < 0) _index = 0;
    final day = _days[_index];
    final weekday = DietWeekday.fromCode(day.dayOfWeek);
    final total =
        day.meals.fold<double>(0, (s, m) => s + m.kcal);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.plan.title,
            style: Typo.mono(11, FontWeight.w600, Palette.textMid)),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v.abs() < 120) return;
          _go(v < 0 ? 1 : -1);
        },
        // Leave the far-left edge free for back gesture.
        dragStartBehavior: DragStartBehavior.down,
        child: AnimatedSwitcher(
          duration: Motion.pageEnterDuration,
          switchInCurve: Motion.pageEnter,
          transitionBuilder: (child, anim) {
            final entering = child.key == ValueKey(_index);
            final beginOffset = entering
                ? Offset(_direction >= 0 ? 0.25 : -0.25, 0)
                : Offset.zero;
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position:
                    Tween(begin: beginOffset, end: Offset.zero).animate(anim),
                child: child,
              ),
            );
          },
          child: ScreenScroll(
            key: ValueKey(_index),
            topPadding: 4,
            spacing: Space.element,
            children: [
              Row(
                children: [
                  Pressable(
                    onTap: _index > 0 ? () => _go(-1) : null,
                    child: Icon(Icons.chevron_left_rounded,
                        size: 28,
                        color:
                            _index > 0 ? Palette.textHi : Palette.void2),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Eyebrow('Giorno ${_index + 1} di ${_days.length}'),
                        Text(weekday?.long ?? day.dayOfWeek,
                            style: Typo.poster(34)),
                      ],
                    ),
                  ),
                  Pressable(
                    onTap: _index < _days.length - 1 ? () => _go(1) : null,
                    child: Icon(Icons.chevron_right_rounded,
                        size: 28,
                        color: _index < _days.length - 1
                            ? Palette.textHi
                            : Palette.void2),
                  ),
                ],
              ),
              VoltPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Totale giornata',
                          style: Typo.body(14, FontWeight.w600)),
                    ),
                    Text('${total.toInt()} kcal',
                        style:
                            Typo.mono(14, FontWeight.w700, Palette.amber)),
                  ],
                ),
              ),
              for (final meal in day.meals)
                VoltPanel(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => MealDetailView(meal: meal))),
                  child: Row(
                    children: [
                      const Icon(Icons.restaurant_rounded,
                          size: 18, color: Palette.lime),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meal.name,
                                style: Typo.body(15, FontWeight.w700)),
                            Text('${meal.items.length} alimenti',
                                style: Typo.body(12, FontWeight.w400,
                                    Palette.textMid)),
                          ],
                        ),
                      ),
                      Text('${meal.kcal.toInt()} kcal',
                          style: Typo.mono(
                              12, FontWeight.w700, Palette.amber)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
