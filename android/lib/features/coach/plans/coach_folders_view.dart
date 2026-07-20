import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/coach_api.dart';
import '../../../core/models/models.dart';
import '../../../core/providers.dart';
import '../../../design/components/confirm_dialog.dart';
import '../../../design/components/panel.dart';
import '../../../design/components/scaffold.dart';
import '../../../design/components/skeleton.dart';
import '../../../design/components/status_overlay.dart';
import '../../../design/theme.dart';

/// Generic folder manager — port of iOS `CoachFolderListView`, reused for
/// the 3 domains (allenamenti / nutrizione / check). The "Template" folder
/// is pinned and undeletable.
class CoachFoldersView extends ConsumerStatefulWidget {
  const CoachFoldersView({super.key, required this.domain});

  /// allenamenti | nutrizione | check
  final String domain;

  @override
  ConsumerState<CoachFoldersView> createState() => _CoachFoldersViewState();
}

class _CoachFoldersViewState extends ConsumerState<CoachFoldersView> {
  List<CoachFolder>? _folders;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final folders =
          await ref.read(apiClientProvider).coachFolders(widget.domain);
      if (mounted) setState(() => _folders = folders);
    } catch (_) {
      if (mounted && _folders == null) setState(() => _error = true);
    }
  }

  Future<void> _create() async {
    final title = await _prompt('Nuova cartella');
    if (title == null || title.isEmpty) return;
    try {
      await ref.read(apiClientProvider).coachCreateFolder(widget.domain, title);
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Creazione non riuscita');
      }
    }
  }

  Future<void> _rename(CoachFolder f) async {
    final title = await _prompt('Rinomina cartella', initial: f.title);
    if (title == null || title.isEmpty) return;
    try {
      await ref
          .read(apiClientProvider)
          .coachRenameFolder(widget.domain, f.id, title);
      await _load();
    } catch (_) {}
  }

  Future<void> _delete(CoachFolder f) async {
    final ok = await ConfirmCenter.confirm(
      context,
      ConfirmOptions(
        title: 'Eliminare "${f.title}"?',
        subtitle: 'I contenuti tornano tra i non archiviati.',
        icon: Icons.folder_delete_outlined,
        variant: ConfirmVariant.danger,
        confirmLabel: 'Elimina',
      ),
    );
    if (!ok) return;
    try {
      await ref
          .read(apiClientProvider)
          .coachDeleteFolder(widget.domain, f.id);
      await _load();
    } catch (_) {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Eliminazione non riuscita');
      }
    }
  }

  Future<String?> _prompt(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.void0,
        title: Text(title, style: Typo.display(17)),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annulla')),
          TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Salva')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final folders = _folders;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Nuova cartella',
            icon: const Icon(Icons.create_new_folder_outlined,
                color: Palette.textHi),
            onPressed: _create,
          ),
        ],
      ),
      body: ScreenScroll(
        topPadding: 0,
        spacing: Space.element,
        onRefresh: _load,
        children: [
          const ScreenHeader(eyebrow: 'Organizza', title: 'Cartelle'),
          if (folders == null && !_error)
            const AvatarRowsSkeleton(count: 4)
          else if (_error)
            EmptyPanel.network(onCta: () {
              setState(() => _error = false);
              _load();
            })
          else if (folders!.isEmpty)
            const EmptyPanel(
                icon: Icons.folder_open_outlined,
                message: 'Nessuna cartella: creane una con l\'icona in alto.')
          else
            for (final f in folders)
              VoltPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      f.isDefaultTemplates
                          ? Icons.folder_special_rounded
                          : Icons.folder_rounded,
                      size: 20,
                      color: Palette.amber,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(f.title,
                          style: Typo.body(14.5, FontWeight.w600)),
                    ),
                    Text('${f.count}',
                        style: Typo.mono(
                            11, FontWeight.w700, Palette.textLow)),
                    if (!f.isDefaultTemplates)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded,
                            size: 18, color: Palette.textMid),
                        color: Palette.void0,
                        onSelected: (a) =>
                            a == 'rename' ? _rename(f) : _delete(f),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'rename',
                              child: Text('Rinomina',
                                  style:
                                      Typo.body(14, FontWeight.w500))),
                          PopupMenuItem(
                              value: 'delete',
                              child: Text('Elimina',
                                  style: Typo.body(14, FontWeight.w500,
                                      Palette.crimson))),
                        ],
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
