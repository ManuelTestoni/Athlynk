import 'package:flutter/material.dart';

import '../../core/models/session.dart';
import '../theme.dart';
import 'misc.dart';
import 'panel.dart';
import 'pressable.dart';
import 'scaffold.dart';
import 'skeleton.dart';

/// Exercise catalog picker — port of iOS `SessionExercisePickerSheet` /
/// `SubstitutePickerSheet`: search by name or browse by muscle group; the
/// substitute variant shows same-muscle suggestions first with an
/// "Esplora tutti" escape hatch. Loader injected so it serves both apps.
class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({
    super.key,
    required this.search,
    required this.onPick,
    this.similarTo,
    this.title = 'Aggiungi esercizio',
  });

  /// `(query, muscleGroup, similarTo, includeGroups)` → results.
  final Future<ExerciseSearchResponse> Function({
    String q,
    String muscleGroup,
    int? similarTo,
    bool includeGroups,
  }) search;

  final void Function(ExerciseSearchItemDto) onPick;

  /// Catalog id whose similar movements are suggested first (substitution).
  final int? similarTo;
  final String title;

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  final _query = TextEditingController();
  List<ExerciseSearchItemDto>? _results;
  List<MuscleGroupDto> _groups = [];
  String _selectedGroup = '';
  bool _exploreAll = false;
  bool _loading = true;

  bool get _suggestMode => widget.similarTo != null && !_exploreAll;

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
      final res = await widget.search(
        q: _query.text.trim(),
        muscleGroup: _selectedGroup,
        similarTo: _suggestMode ? widget.similarTo : null,
        includeGroups: _groups.isEmpty,
      );
      if (!mounted) return;
      setState(() {
        _results = res.results;
        if (res.muscleGroups != null) _groups = res.muscleGroups!;
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
      appBar: AppBar(title: Text(widget.title, style: Typo.display(18))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.screenH, 6, Space.screenH, 10),
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
                        hintText: 'Cerca un esercizio…',
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
          if (_suggestMode)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Space.screenH),
              child: Row(
                children: [
                  const Expanded(child: Eyebrow('Suggeriti · stesso muscolo')),
                  TextButton(
                    onPressed: () {
                      setState(() => _exploreAll = true);
                      _load();
                    },
                    child: Text('Esplora tutti',
                        style:
                            Typo.body(13, FontWeight.w700, Palette.cyan)),
                  ),
                ],
              ),
            )
          else if (_groups.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: Space.screenH),
                children: [
                  _groupChip('', 'Tutti'),
                  for (final g in _groups) _groupChip(g.slug, g.name),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(Space.screenH),
                    child: AvatarRowsSkeleton(count: 6),
                  )
                : (_results == null || _results!.isEmpty)
                    ? const Padding(
                        padding: EdgeInsets.all(Space.screenH),
                        child: EmptyPanel(
                          icon: Icons.search_off_rounded,
                          message: 'Nessun esercizio trovato.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                            Space.screenH, 4, Space.screenH, 30),
                        itemCount: _results!.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final ex = _results![i];
                          return Pressable(
                            onTap: () => widget.onPick(ex),
                            child: Container(
                              decoration: voltPanel(),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  ExerciseThumb(url: ex.coverImage),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(ex.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Typo.body(
                                                14.5, FontWeight.w600)),
                                        if (ex.primaryMuscle.isNotEmpty)
                                          Text(ex.primaryMuscle,
                                              style: Typo.mono(
                                                  10,
                                                  FontWeight.w600,
                                                  Palette.textLow)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.add_circle_outline_rounded,
                                      size: 20, color: Palette.lime),
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

  Widget _groupChip(String slug, String label) {
    final selected = _selectedGroup == slug;
    return Pressable(
      onTap: () {
        setState(() => _selectedGroup = slug);
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Palette.textHi : Palette.void1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Palette.line),
        ),
        child: Text(
          label,
          style: Typo.body(12.5, FontWeight.w600,
              selected ? Palette.void0 : Palette.textMid),
        ),
      ),
    );
  }
}
