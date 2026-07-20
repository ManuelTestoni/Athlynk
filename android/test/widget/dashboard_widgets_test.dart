import 'package:athlynk/core/models/models.dart';
import 'package:athlynk/design/components/dashboard_edit_sheet.dart';
import 'package:athlynk/design/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The customizable dashboard is the newest cross-platform feature: array
/// order is canonical and `y` is rewritten to the index on every mutation,
/// so the web grid re-flows to the mobile ordering.
void main() {
  const catalog = [
    WidgetCatalogItemDto(
        type: 'next_workout',
        title: 'Prossimo allenamento',
        desc: 'La sessione di oggi',
        mobileSize: 'full'),
    WidgetCatalogItemDto(
        type: 'weight_trend',
        title: 'Andamento peso',
        desc: 'Il tuo peso nel tempo',
        mobileSize: 'full'),
    WidgetCatalogItemDto(
        type: 'checks_due', title: 'Check da compilare', mobileSize: 'full'),
  ];

  const placed = [
    DashboardWidgetDto(id: 'w1', type: 'next_workout', y: 0),
    DashboardWidgetDto(id: 'w2', type: 'weight_trend', y: 1),
  ];

  Future<List<DashboardWidgetDto>?> pumpSheet(WidgetTester tester) async {
    List<DashboardWidgetDto>? emitted;
    await tester.pumpWidget(MaterialApp(
      theme: athlynkTheme(),
      home: DashboardEditSheet(
        widgets: placed,
        catalog: catalog,
        onChanged: (w) => emitted = w,
        onReset: () {},
      ),
    ));
    await tester.pumpAndSettle();
    return emitted;
  }

  testWidgets('lists active widgets by catalog title and offers the unplaced',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text('Prossimo allenamento'), findsOneWidget);
    expect(find.text('Andamento peso'), findsOneWidget);
    // Only the widget that isn't placed shows up under "Aggiungi widget".
    expect(find.text('Check da compilare'), findsOneWidget);
    expect(find.text('Widget attivi'.toUpperCase()), findsOneWidget);
    expect(find.text('Aggiungi widget'.toUpperCase()), findsOneWidget);
  });

  testWidgets('removing a widget emits the shortened list', (tester) async {
    List<DashboardWidgetDto>? emitted;
    await tester.pumpWidget(MaterialApp(
      theme: athlynkTheme(),
      home: DashboardEditSheet(
        widgets: placed,
        catalog: catalog,
        onChanged: (w) => emitted = w,
        onReset: () {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.remove_circle_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(emitted, isNotNull);
    expect(emitted!.map((w) => w.type), ['weight_trend']);
  });

  testWidgets('adding from the catalog appends with the catalog size',
      (tester) async {
    List<DashboardWidgetDto>? emitted;
    await tester.pumpWidget(MaterialApp(
      theme: athlynkTheme(),
      home: DashboardEditSheet(
        widgets: placed,
        catalog: catalog,
        onChanged: (w) => emitted = w,
        onReset: () {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();

    expect(emitted!.map((w) => w.type),
        ['next_workout', 'weight_trend', 'checks_due']);
    expect(emitted!.last.size, 'full');
  });

  testWidgets('reset button is wired to the caller', (tester) async {
    var reset = false;
    await tester.pumpWidget(MaterialApp(
      theme: athlynkTheme(),
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => DashboardEditSheet(
            widgets: placed,
            catalog: catalog,
            onChanged: (_) {},
            onReset: () => reset = true,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ripristina'));
    await tester.pumpAndSettle();

    expect(reset, isTrue);
  });
}
