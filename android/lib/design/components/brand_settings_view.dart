import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/athlete_api.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../theme.dart';
import 'neon_button.dart';
import 'panel.dart';
import 'pressable.dart';
import 'status_overlay.dart';

/// "Aspetto" — brand name + two brand colors, persisted server-side and
/// applied app-wide (port of iOS `BrandSettingsView`). Shared by both roles.
class BrandSettingsView extends ConsumerStatefulWidget {
  const BrandSettingsView({
    super.key,
    this.initialName,
    this.initialPrimary,
    this.initialAccent,
  });

  final String? initialName;
  final String? initialPrimary;
  final String? initialAccent;

  @override
  ConsumerState<BrandSettingsView> createState() => _BrandSettingsViewState();
}

class _BrandSettingsViewState extends ConsumerState<BrandSettingsView> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late Color _primary = colorFromHexString(widget.initialPrimary) ??
      Palette.defaultPrimary;
  late Color _accent =
      colorFromHexString(widget.initialAccent) ?? Palette.defaultAccent;
  bool _saving = false;

  static const _swatches = [
    Palette.defaultPrimary,
    Palette.defaultAccent,
    Color(0xFF3F7A5E),
    Color(0xFF132A47),
    Color(0xFFB8860B),
    Color(0xFF5C4A6B),
    Color(0xFFA23B3B),
    Color(0xFF0B1D3A),
    Color(0xFF7C3AED),
    Color(0xFF0E7490),
    Color(0xFFB45309),
    Color(0xFF166534),
  ];

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).updateProfile({
        'brand_name': _name.text.trim(),
        'brand_primary': _primary.hexString,
        'brand_accent': _accent.hexString,
      });
      await ref.read(sessionControllerProvider.notifier).applyBrand(
            primaryHex: _primary.hexString,
            accentHex: _accent.hexString,
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException {
      if (mounted) {
        StatusFlash.show(context,
            success: false, message: 'Salvataggio non riuscito');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    setState(() {
      _primary = Palette.defaultPrimary;
      _accent = Palette.defaultAccent;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(title: Text('Aspetto', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          const Eyebrow('Nome brand'),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            style: Typo.body(15, FontWeight.w600),
            decoration:
                const InputDecoration(hintText: 'Il tuo brand (facoltativo)'),
          ),
          const SizedBox(height: 22),
          _picker('Colore primario', _primary, (c) => setState(() => _primary = c)),
          const SizedBox(height: 18),
          _picker('Colore accento', _accent, (c) => setState(() => _accent = c)),
          const SizedBox(height: 22),
          Container(
            decoration: voltPanel(),
            padding: const EdgeInsets.all(Space.card),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Anteprima CTA',
                      style: Typo.body(13, FontWeight.w700, Palette.void0)),
                ),
                const SizedBox(width: 12),
                Text('Link e controlli',
                    style: Typo.body(13.5, FontWeight.w600, _accent)),
              ],
            ),
          ),
          const SizedBox(height: 26),
          NeonButton('Salva', loading: _saving, onTap: _save),
          const SizedBox(height: 10),
          NeonButton('Ripristina colori Athlynk',
              filled: false, color: Palette.textMid, onTap: _reset),
        ],
      ),
    );
  }

  Widget _picker(String label, Color value, ValueChanged<Color> onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in _swatches)
              Pressable(
                onTap: () => onPick(c),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: value.toARGB32() == c.toARGB32()
                          ? Palette.textHi
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: value.toARGB32() == c.toARGB32()
                      ? const Icon(Icons.check_rounded,
                          size: 17, color: Palette.void0)
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
