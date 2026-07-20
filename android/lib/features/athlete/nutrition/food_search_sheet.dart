import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/athlete_api.dart';
import '../../../core/l10n/formatters.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/neon_button.dart';
import '../../../design/components/pressable.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/theme.dart';

/// Food picker for the MACRO diary — port of iOS `FoodSearchSheet` (+ its
/// pushed `QuantityView`): search / category / recent filters, then a gram
/// slider with live macro preview.
class FoodSearchSheet extends ConsumerStatefulWidget {
  const FoodSearchSheet({
    super.key,
    required this.assignmentId,
    this.date,
    required this.onLogged,
  });

  final int assignmentId;
  final String? date;
  final VoidCallback onLogged;

  @override
  ConsumerState<FoodSearchSheet> createState() => _FoodSearchSheetState();
}

enum _FoodFilter { all, recent, category }

class _FoodSearchSheetState extends ConsumerState<FoodSearchSheet> {
  final _query = TextEditingController();
  List<FoodDto>? _results;
  List<String> _categories = [];
  String? _category;
  _FoodFilter _filter = _FoodFilter.all;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(apiClientProvider).searchFoods(
            _query.text.trim(),
            filter: _filter == _FoodFilter.recent ? 'recent' : null,
            cat: _filter == _FoodFilter.category ? _category : null,
            includeCats: _categories.isEmpty,
          );
      if (!mounted) return;
      setState(() {
        _results = res.results;
        if (res.categories != null) _categories = res.categories!;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = const [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text('Aggiungi alimento', style: Typo.display(18))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.screenH, 6, Space.screenH, 8),
            child: Container(
              decoration: voltPanel(radius: Radii.field),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 18, color: Palette.textLow),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      style: Typo.body(15, FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Cerca un alimento…',
                        hintStyle:
                            Typo.body(15, FontWeight.w400, Palette.textLow),
                        border: InputBorder.none,
                      ),
                      onChanged: (_) => _load(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.screenH),
              children: [
                _chip('Tutti', _filter == _FoodFilter.all, () {
                  setState(() {
                    _filter = _FoodFilter.all;
                    _category = null;
                  });
                  _load();
                }),
                _chip('Recenti', _filter == _FoodFilter.recent, () {
                  setState(() => _filter = _FoodFilter.recent);
                  _load();
                }),
                for (final c in _categories)
                  _chip(c, _filter == _FoodFilter.category && _category == c,
                      () {
                    setState(() {
                      _filter = _FoodFilter.category;
                      _category = c;
                    });
                    _load();
                  }),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(Space.screenH),
                    child: AvatarRowsSkeleton(count: 7),
                  )
                : (_results == null || _results!.isEmpty)
                    ? const Padding(
                        padding: EdgeInsets.all(Space.screenH),
                        child: EmptyPanel(
                            icon: Icons.search_off_rounded,
                            message: 'Nessun alimento trovato.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            Space.screenH, 4, Space.screenH, 30),
                        itemCount: _results!.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final food = _results![i];
                          return Pressable(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => _QuantityView(
                                  food: food,
                                  assignmentId: widget.assignmentId,
                                  date: widget.date,
                                  onLogged: widget.onLogged,
                                ),
                              ),
                            ),
                            child: Container(
                              decoration: voltPanel(),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(food.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Typo.body(
                                                14.5, FontWeight.w600)),
                                        Text(
                                          'per 100 g · P ${food.protein.toInt()} C ${food.carb.toInt()} F ${food.fat.toInt()}',
                                          style: Typo.mono(9.5,
                                              FontWeight.w600, Palette.textMid),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text('${food.kcal.toInt()} kcal',
                                      style: Typo.mono(11, FontWeight.w700,
                                          Palette.amber)),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.chevron_right_rounded,
                                      size: 16, color: Palette.textLow),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Palette.textHi : Palette.void1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Palette.line),
        ),
        child: Text(label,
            style: Typo.body(12.5, FontWeight.w600,
                selected ? Palette.void0 : Palette.textMid)),
      ),
    );
  }
}

/// Gram slider + live macro preview → POST macro-log.
class _QuantityView extends ConsumerStatefulWidget {
  const _QuantityView({
    required this.food,
    required this.assignmentId,
    required this.date,
    required this.onLogged,
  });

  final FoodDto food;
  final int assignmentId;
  final String? date;
  final VoidCallback onLogged;

  @override
  ConsumerState<_QuantityView> createState() => _QuantityViewState();
}

class _QuantityViewState extends ConsumerState<_QuantityView> {
  double _grams = 100;
  final _mealName = TextEditingController();
  bool _saving = false;

  double _scaled(double per100) => per100 * _grams / 100;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).addMacroLog(
            assignment: widget.assignmentId,
            foodId: widget.food.id,
            quantityG: _grams,
            mealName:
                _mealName.text.trim().isEmpty ? null : _mealName.text.trim(),
            date: widget.date,
          );
      if (!mounted) return;
      widget.onLogged();
      // Close the whole sheet (quantity + search live in the sheet's
      // nested navigator; popping the sheet route closes both).
      Navigator.of(context, rootNavigator: true).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(title: Text(food.name, style: Typo.display(17))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          Center(
            child: Column(
              children: [
                Text('${Formatters.decimal(_grams, maxDecimals: 0)} g',
                    style: Typo.poster(52)),
                Text('${_scaled(food.kcal).toInt()} kcal',
                    style: Typo.mono(14, FontWeight.w700, Palette.amber)),
              ],
            ),
          ),
          Slider(
            value: _grams,
            min: 5,
            max: 500,
            divisions: 99,
            activeColor: Palette.cyan,
            onChanged: (v) => setState(() => _grams = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _macro('Proteine', _scaled(food.protein), Palette.magenta),
              _macro('Carboidrati', _scaled(food.carb), Palette.cyan),
              _macro('Grassi', _scaled(food.fat), Palette.lime),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _mealName,
            style: Typo.body(14.5, FontWeight.w500),
            decoration: const InputDecoration(
                labelText: 'Pasto (es. Pranzo — facoltativo)'),
          ),
          const SizedBox(height: 26),
          NeonButton('Registra', loading: _saving, onTap: _save),
        ],
      ),
    );
  }

  Widget _macro(String label, double grams, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: voltPanel(radius: 14),
        child: Column(
          children: [
            Text('${grams.toInt()}g', style: Typo.poster(20)),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
                style: Typo.mono(7, FontWeight.w700, color)
                    .copyWith(letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
