import 'dart:async';

import 'package:athlynk/design/components/confirm_dialog.dart';
import 'package:athlynk/design/components/neon_button.dart';
import 'package:athlynk/design/components/scaffold.dart';
import 'package:athlynk/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        theme: athlynkTheme(),
        home: Scaffold(body: Center(child: child)),
      );

  group('NeonButton', () {
    testWidgets('fires onTap and swaps to a spinner while loading',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(NeonButton('Accedi', onTap: () => taps++)));

      await tester.tap(find.text('Accedi'));
      await tester.pump();
      expect(taps, 1);

      await tester.pumpWidget(
          host(NeonButton('Accedi', loading: true, onTap: () => taps++)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Accedi'), findsNothing);
    });

    testWidgets('a loading button ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
          host(NeonButton('Salva', loading: true, onTap: () => taps++)));

      await tester.tap(find.byType(NeonButton));
      await tester.pump();

      expect(taps, 0);
    });
  });

  group('ConfirmCenter', () {
    testWidgets('resolves true on confirm and false on cancel',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: athlynkTheme(),
        home: Builder(builder: (context) {
          ctx = context;
          return const Scaffold();
        }),
      ));

      final confirmed = ConfirmCenter.confirm(
        ctx,
        const ConfirmOptions(
          title: 'Eliminare questo piano?',
          variant: ConfirmVariant.danger,
          confirmLabel: 'Elimina',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Eliminare questo piano?'), findsOneWidget);
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();
      expect(await confirmed, isTrue);

      final cancelled = ConfirmCenter.confirm(
        ctx,
        const ConfirmOptions(title: 'Uscire?'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annulla'));
      await tester.pumpAndSettle();
      expect(await cancelled, isFalse);
    });
  });

  group('EmptyPanel', () {
    testWidgets('network variant shows the Italian retry affordance',
        (tester) async {
      var retried = false;
      await tester
          .pumpWidget(host(EmptyPanel.network(onCta: () => retried = true)));

      expect(
          find.text('Problema di connessione. Controlla la rete e riprova.'),
          findsOneWidget);
      await tester.tap(find.text('Riprova'));
      await tester.pump();
      expect(retried, isTrue);
    });
  });

  group('SettingsToggleRow', () {
    testWidgets('flips instantly (optimistic mirror) before the API resolves',
        (tester) async {
      final completer = Completer<void>();
      var requested = false;

      await tester.pumpWidget(host(SettingsToggleRow(
        title: 'Nuovo check',
        value: false,
        onChanged: (v) {
          requested = v;
          return completer.future;
        },
      )));

      await tester.tap(find.byType(Switch));
      await tester.pump();

      // Backend hasn't answered yet, the switch is already on.
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(requested, isTrue);
      completer.complete();
      await tester.pumpAndSettle();
    });
  });

  group('theme tokens', () {
    test('palette matches the iOS Greek-luxury values', () {
      expect(Palette.void0, const Color(0xFFFFFFFF));
      expect(Palette.void1, const Color(0xFFF4F6F9));
      expect(Palette.void2, const Color(0xFFE8ECF2));
      expect(Palette.textHi, const Color(0xFF0B1D3A));
      expect(Palette.lime, const Color(0xFF3F7A5E));
      expect(Palette.amber, const Color(0xFFB8860B));
      expect(Palette.crimson, const Color(0xFFA23B3B));
      expect(Palette.defaultPrimary, const Color(0xFF1E3A5F));
      expect(Palette.defaultAccent, const Color(0xFF5B89B6));
    });

    test('layout constants mirror the iOS scaffold', () {
      expect(Space.screenH, 22);
      expect(Space.section, 22);
      expect(AppLayout.tabBarClearance, 120);
      expect(Motion.staggerStep, 0.07);
    });
  });
}
