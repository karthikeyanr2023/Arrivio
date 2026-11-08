import 'package:arrivio_app/api.dart';
import 'package:arrivio_app/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApi extends ArrivioApi {
  final calls = <(String, Map<String, dynamic>?)>[];
  bool failDistance = false;

  @override
  Future<dynamic> request(String url, {Map<String, dynamic>? body}) async {
    calls.add((url, body));
    if (url == ArrivioApi.geocode) return {'lat': 0, 'lng': -10};
    if (url == ArrivioApi.distance) {
      if (failDistance) throw Exception('distance service unavailable');
      return {
        'data': [
          {'businessTitle': 'Near shop', 'distanceMiles': 4.5},
          {'businessTitle': 'Far shop', 'distanceMiles': 8},
          {'businessTitle': 'Boundary shop', 'distanceMiles': 50},
          {'businessTitle': 'Outer shop', 'distanceMiles': 100},
          {'businessTitle': 'Beyond shop', 'distanceMiles': 100.01},
        ],
      };
    }
    throw StateError('Unexpected URL: $url');
  }
}

void main() {
  testWidgets('destination resolves and proximity filters merchants', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          username: 'User',
          profile: const {},
          isMerchant: false,
          api: api,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Example address');
    await tester.tap(find.text('Set destination'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("What's the occasion?"), findsOneWidget);
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    expect(api.calls[0].$1, ArrivioApi.geocode);
    expect(api.calls[0].$2, {
      'address': 'Example address',
      'addressText': 'Example address',
    });
    expect(api.calls[1].$2, {
      'lat': 0,
      'lng': -10,
      'userId': 'User',
      'occasion': 'Family',
    });
    expect(
      find.textContaining('occasion ranking could not be confirmed'),
      findsOneWidget,
    );
    expect(find.text('Near shop'), findsOneWidget);
    expect(find.text('Far shop'), findsNothing);
    expect(find.text('5 miles'), findsOneWidget);
    expect(find.text('10 miles'), findsOneWidget);
    expect(find.text('15 miles'), findsNothing);
    expect(find.text('50 miles'), findsOneWidget);
    expect(find.text('100 miles'), findsOneWidget);
    await tester.tap(find.text('10 miles'));
    await tester.pumpAndSettle();
    expect(find.text('Far shop'), findsOneWidget);
    expect(find.text('Boundary shop'), findsNothing);
    await tester.tap(find.text('50 miles'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Boundary shop'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Boundary shop'), findsOneWidget);
    expect(find.text('Outer shop'), findsNothing);
    expect(find.text('Beyond shop'), findsNothing);
    await tester.ensureVisible(find.text('100 miles'));
    await tester.tap(find.text('100 miles'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Outer shop'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Outer shop'), findsOneWidget);
    expect(find.text('Beyond shop'), findsNothing);
  });

  testWidgets('distance failure is displayed', (tester) async {
    final api = FakeApi()..failDistance = true;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          username: 'User',
          profile: const {},
          isMerchant: false,
          api: api,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Example address');
    await tester.tap(find.text('Set destination'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Skip'));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unable to find nearby merchants'),
      findsOneWidget,
    );
  });

  testWidgets('disabling the occasion dialog lasts for the login session', (
    tester,
  ) async {
    final api = FakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          username: 'User',
          profile: const {},
          isMerchant: false,
          api: api,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Example address');
    await tester.tap(find.text('Set destination'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text("Don't show this again"));
    await tester.tap(find.text("Don't show this again"));
    await tester.pumpAndSettle();
    expect(api.calls[1].$2?['occasion'], '');
    await tester.tap(find.text('Set destination'));
    await tester.pumpAndSettle();
    expect(find.text("What's the occasion?"), findsNothing);
    expect(api.calls[3].$2?['occasion'], '');
  });
}
