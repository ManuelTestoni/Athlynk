import 'package:athlynk/app/athlynk_app.dart';
import 'package:athlynk/design/components/volt_field.dart';
import 'package:athlynk/design/theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the crash that made the app unusable on Android:
/// `AthlynkApp` declares `it_IT` as its only supported locale, and the
/// `Default*Localizations` that `MaterialApp` falls back to only cover `en`.
/// Without the Global* delegates, `MaterialLocalizations.of(context)` resolves
/// to nothing and every `TextField` throws
/// "No MaterialLocalizations found. TextField widgets require
/// MaterialLocalizations to be provided by a Localizations widget ancestor."
Widget _app(Widget home) => MaterialApp(
      theme: athlynkTheme(),
      locale: appLocale,
      supportedLocales: appSupportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: home,
    );

void main() {
  testWidgets('a TextField builds under the app it_IT locale', (tester) async {
    await tester.pumpWidget(_app(
      const Scaffold(
        body: VoltField(hint: 'Email', icon: Icons.mail_outline),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a@b.it');
    await tester.pump();
    expect(find.text('a@b.it'), findsOneWidget);
  });

  testWidgets('Material/Widgets/Cupertino localizations all resolve to it',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      ctx = context;
      return const SizedBox.shrink();
    })));

    expect(Localizations.localeOf(ctx), appLocale);
    // `.of` asserts the delegate is present, so these calls are the check.
    expect(MaterialLocalizations.of(ctx).okButtonLabel, isNotEmpty);
    expect(CupertinoLocalizations.of(ctx).copyButtonLabel, isNotEmpty);
    // Italian strings actually shipped, not the English fallback.
    expect(MaterialLocalizations.of(ctx).cancelButtonLabel, 'Annulla');
  });
}
