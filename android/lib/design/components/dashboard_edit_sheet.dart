import 'package:flutter/material.dart';

import '../../core/models/dashboard.dart';
import '../../core/utils/haptics.dart';
import '../theme.dart';
import 'panel.dart';
import 'pressable.dart';

/// Role-agnostic dashboard layout editor — port of iOS `DashboardEditSheet`:
/// reorder/remove the active widgets + add from the catalog; `y` is
/// normalized to the array index on every mutation by the caller.
class DashboardEditSheet extends StatefulWidget {
  const DashboardEditSheet({
    super.key,
    required this.widgets,
    required this.catalog,
    required this.onChanged,
    required this.onReset,
    this.onConfigure,
  });

  final List<DashboardWidgetDto> widgets;
  final List<WidgetCatalogItemDto> catalog;
  final ValueChanged<List<DashboardWidgetDto>> onChanged;
  final VoidCallback onReset;

  /// Coach: per-widget "Scegli" hook (pinned athletes picker).
  final void Function(DashboardWidgetDto)? onConfigure;

  @override
  State<DashboardEditSheet> createState() => _DashboardEditSheetState();
}

class _DashboardEditSheetState extends State<DashboardEditSheet> {
  late final List<DashboardWidgetDto> _widgets = List.of(widget.widgets);

  List<WidgetCatalogItemDto> get _unplaced {
    final placed = _widgets.map((w) => w.type).toSet();
    return widget.catalog.where((c) => !placed.contains(c.type)).toList();
  }

  void _commit() => widget.onChanged(List.of(_widgets));

  String _titleFor(String type) {
    for (final c in widget.catalog) {
      if (c.type == type) return c.title;
    }
    return type;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
        title: Text('Personalizza', style: Typo.display(19)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.tap();
              widget.onReset();
              Navigator.of(context).pop();
            },
            child: Text('Ripristina',
                style: Typo.body(14, FontWeight.w600, Palette.crimson)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Space.screenH, 10, Space.screenH, 40),
        children: [
          const Eyebrow('Widget attivi'),
          const SizedBox(height: 10),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, _, _) => Material(
              color: Colors.transparent,
              child: Transform.scale(scale: 1.02, child: child),
            ),
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final item = _widgets.removeAt(oldIndex);
                _widgets.insert(newIndex, item);
              });
              Haptics.soft();
              _commit();
            },
            children: [
              for (final (i, w) in _widgets.indexed)
                Padding(
                  key: ValueKey(w.id),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: voltPanel(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_indicator_rounded,
                              size: 20, color: Palette.textLow),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_titleFor(w.type),
                              style: Typo.body(15, FontWeight.w600)),
                        ),
                        if (widget.onConfigure != null &&
                            w.type == 'pinned_athletes')
                          TextButton(
                            onPressed: () => widget.onConfigure!(w),
                            child: Text('Scegli',
                                style: Typo.body(
                                    13, FontWeight.w700, Palette.cyan)),
                          ),
                        Pressable(
                          onTap: () {
                            setState(() => _widgets.removeAt(i));
                            _commit();
                          },
                          child: const Icon(Icons.remove_circle_outline_rounded,
                              size: 20, color: Palette.crimson),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (_unplaced.isNotEmpty) ...[
            const SizedBox(height: Space.section),
            const Eyebrow('Aggiungi widget'),
            const SizedBox(height: 10),
            for (final c in _unplaced)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: voltPanel(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: Typo.body(15, FontWeight.w600)),
                            if (c.desc.isNotEmpty)
                              Text(c.desc,
                                  style: Typo.body(
                                      12, FontWeight.w400, Palette.textLow)),
                          ],
                        ),
                      ),
                      Pressable(
                        onTap: () {
                          setState(() {
                            _widgets.add(DashboardWidgetDto(
                              id: '${c.type}-${DateTime.now().millisecondsSinceEpoch}',
                              type: c.type,
                              size: c.mobileSize,
                            ));
                          });
                          _commit();
                        },
                        child: const Icon(Icons.add_circle_outline_rounded,
                            size: 22, color: Palette.lime),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
