import 'package:flutter/material.dart';

import '../../core/l10n/formatters.dart';
import '../../core/models/progress.dart';
import '../theme.dart';
import 'measurement_trends.dart';
import 'neon_button.dart';
import 'panel.dart';
import 'pressable.dart';

/// Manual measurement entry (peso / circonferenza / plica for a chosen day) —
/// port of iOS `AddMeasurementSheet`. Shared by athlete (self) and coach (per
/// client) via the injected [onSubmit].
class AddMeasurementSheet extends StatefulWidget {
  const AddMeasurementSheet({
    super.key,
    required this.catalog,
    required this.onSubmit,
  });

  final MeasurementCatalog catalog;
  final Future<bool> Function(
      {required String type,
      String? siteKey,
      required double value,
      required String date}) onSubmit;

  @override
  State<AddMeasurementSheet> createState() => _AddMeasurementSheetState();
}

enum _MType {
  weight('Peso', 'kg'),
  circumference('Circonferenza', 'cm'),
  skinfold('Plica', 'mm');

  const _MType(this.label, this.unit);
  final String label;
  final String unit;
}

class _AddMeasurementSheetState extends State<AddMeasurementSheet> {
  _MType _type = _MType.weight;
  String? _site;
  final _value = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  List<MeasurementOption> get _sites => switch (_type) {
        _MType.weight => const [],
        _MType.circumference => widget.catalog.circumferences,
        _MType.skinfold => widget.catalog.skinfolds,
      };

  Future<void> _save() async {
    final v = Formatters.parseDecimal(_value.text);
    if (v == null || v <= 0) {
      setState(() => _error = "Dev'essere un numero maggiore di 0.");
      return;
    }
    if (_type != _MType.weight && _site == null) {
      setState(() => _error = 'Seleziona un distretto.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSubmit(
      type: switch (_type) {
        _MType.weight => 'weight',
        _MType.circumference => 'circumference',
        _MType.skinfold => 'skinfold',
      },
      siteKey: _type == _MType.weight ? null : _site,
      value: v,
      date:
          '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.void0,
      appBar: AppBar(
          title: Text('Nuova misurazione', style: Typo.display(18))),
      body: ListView(
        padding: const EdgeInsets.all(Space.screenH),
        children: [
          const Eyebrow('Tipo'),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final t in _MType.values)
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() {
                      _type = t;
                      _site = null;
                    }),
                    child: AnimatedContainer(
                      duration: Motion.snappyDuration,
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t == _type ? Palette.cyan : Palette.void1,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(
                        t.label,
                        style: Typo.body(12.5, FontWeight.w700,
                            t == _type ? Palette.void0 : Palette.textMid),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_sites.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Eyebrow('Distretto'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in _sites)
                  Pressable(
                    onTap: () => setState(() => _site = s.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: s.key == _site
                            ? Palette.violet
                            : Palette.void1,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Palette.line),
                      ),
                      child: Text(
                        s.label.isEmpty
                            ? measurementSiteLabel(s.key)
                            : s.label,
                        style: Typo.mono(10.5, FontWeight.w600,
                            s.key == _site ? Palette.void0 : Palette.textMid),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          const Eyebrow('Valore'),
          const SizedBox(height: 10),
          TextField(
            controller: _value,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: Typo.mono(22, FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0,0',
              suffixText: _type.unit,
              suffixStyle: Typo.mono(14, FontWeight.w600, Palette.textMid),
            ),
          ),
          const SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Data', style: Typo.body(14, FontWeight.w600)),
            trailing: Text(Formatters.mediumDate(_date),
                style: Typo.mono(13, FontWeight.w600, Palette.cyan)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate:
                    DateTime.now().subtract(const Duration(days: 365 * 3)),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: Typo.body(13, FontWeight.w600, Palette.crimson)),
            ),
          const SizedBox(height: 22),
          NeonButton('Salva', loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
