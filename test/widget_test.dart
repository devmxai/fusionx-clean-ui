// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:fusionx_clean_ui/app.dart';

void main() {
  testWidgets('Clean UI app renders the integrated editor shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FusionXCleanUiApp());

    expect(find.byType(FusionXCleanUiApp), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Lip Sync'), findsOneWidget);
  });
}
