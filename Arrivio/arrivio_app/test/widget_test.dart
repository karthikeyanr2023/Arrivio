import 'package:arrivio_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login keeps only the user profile option', (tester) async {
    await tester.pumpWidget(const ArrivioApp());
    expect(find.text('User Profile'), findsOneWidget);
    expect(find.text('Merchant Profile'), findsNothing);
    expect(find.text('Arrivio'), findsOneWidget);
    expect(find.textContaining('Passwords are not verified'), findsOneWidget);
    await tester.tap(find.text('Login'));
    await tester.pump();
    expect(find.text('Please enter a user name.'), findsOneWidget);
  });

  testWidgets('user profile opens registration', (tester) async {
    await tester.pumpWidget(const ArrivioApp());
    await tester.tap(find.text('User Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Create your Arrivio profile'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });
}
