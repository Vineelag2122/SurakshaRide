// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:suraksharide_frontend/suraksharide_app.dart';

void main() {
  testWidgets('SurakshaRide launches and allows demo rider login', (WidgetTester tester) async {
    await tester.pumpWidget(const SurakshaRideApp());

    expect(find.text('SurakshaRide'), findsWidgets);
    expect(find.textContaining('parametric income protection'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'rider@demo.com');
    await tester.enterText(find.byType(TextField).at(1), 'demo123');
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Rider Console'), findsOneWidget);
    expect(find.text('Coverage cap'), findsOneWidget);
  });
}
