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
  testWidgets('SurakshaRide launches intro then login experience', (WidgetTester tester) async {
    await tester.pumpWidget(const SurakshaRideApp());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('SurakshaRide'), findsWidgets);
    expect(find.textContaining('Income protection built for delivery riders.'), findsOneWidget);
    expect(find.text('Go to Login'), findsOneWidget);

    await tester.tap(find.text('Go to Login'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });
}
