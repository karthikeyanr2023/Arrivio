import 'dart:async';

import 'package:arrivio_app/api.dart';
import 'package:arrivio_app/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeApi extends ArrivioApi {
  final calls = <(String, Map<String, dynamic>?)>[];
  bool failDistance = false;
  Completer<dynamic>? distanceResponse;

  @override
  Future<dynamic> request(String url, {Map<String, dynamic>? body}) async {
    calls.add((url, body));
    if (url == ArrivioApi.geocode) return {'lat': 0, 'lng': -10};
    if (url == ArrivioApi.distance) {
      if (failDistance) throw Exception('distance service unavailable');
      if (distanceResponse != null) return distanceResponse!.future;
      return {
        'data': [
          {
            'businessTitle': 'Near shop',
            'distanceMiles': 4.5,
            'deals': [
              {
                'title': 'Special deal',
                'details': 'Free drink',
                'to': '2099-12-31',
              },
              {'title': 'Old deal', 'to': '2000-01-01'},
            ],
            'coupons': [
              {'title': 'Save today', 'details': 'Save 5'},
            ],
          },
          {
            'businessTitle': 'No offers',
            'distanceMiles': 1,
            'deals': [],
            'coupons': [],
          },
          {
            'businessTitle': 'Expired only',
            'distanceMiles': 1,
            'deals': [
              {'to': '2000-01-01'},
            ],
            'coupons': [],
          },
          {'businessTitle': 'Missing offers', 'distanceMiles': 1},
          {
            'businessTitle': 'Far shop',
            'distanceMiles': 8,
            'deals': [],
            'coupons': [
              {'title': 'Coupon'},
            ],
          },
          {
            'businessTitle': 'Boundary shop',
            'distanceMiles': 50,
            'deals': [
              {'title': 'Deal'},
            ],
            'coupons': [],
          },
          {
            'businessTitle': 'Outer shop',
            'distanceMiles': 100,
            'deals': [
              {'title': 'Deal'},
            ],
            'coupons': [],
          },
          {
            'businessTitle': 'Beyond shop',
            'distanceMiles': 100.01,
            'deals': [
              {'title': 'Deal'},
            ],
            'coupons': [],
          },
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
    expect(find.text('No offers'), findsNothing);
    expect(find.text('Expired only'), findsNothing);
    expect(find.text('Missing offers'), findsNothing);
    expect(
      find.textContaining('Offer information is unavailable'),
      findsOneWidget,
    );
    expect(find.text('1 Deal'), findsOneWidget);
    expect(find.text('1 Coupon'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 Deal'));
    await tester.pumpAndSettle();
    expect(find.text('Special deal'), findsOneWidget);
    expect(find.text('Free drink'), findsOneWidget);
    expect(find.text('Old deal'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1 Coupon'));
    await tester.tap(find.text('1 Coupon'));
    await tester.pumpAndSettle();
    expect(find.text('Save today'), findsOneWidget);
    expect(find.text('Save 5'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Far shop'), findsNothing);
    expect(find.text('5 miles'), findsOneWidget);
    expect(find.text('10 miles'), findsOneWidget);
    expect(find.text('15 miles'), findsNothing);
    expect(find.text('50 miles'), findsOneWidget);
    expect(find.text('100 miles'), findsOneWidget);
    await tester.ensureVisible(find.text('10 miles'));
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
    await tester.drag(find.byType(ListView), const Offset(0, 600));
    await tester.pumpAndSettle();
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

  testWidgets('shows offer retrieval progress and empty results', (
    tester,
  ) async {
    final api = FakeApi()..distanceResponse = Completer<dynamic>();
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Retrieving deals and coupons...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.distanceResponse!.complete({
      'data': [
        {'distanceMiles': 1, 'deals': [], 'coupons': []},
      ],
    });
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No merchants with active deals or coupons were found within 5 miles.',
      ),
      findsOneWidget,
    );
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
