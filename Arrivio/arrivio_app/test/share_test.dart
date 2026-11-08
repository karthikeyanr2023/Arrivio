import 'dart:async';

import 'package:arrivio_app/home.dart';
import 'package:arrivio_app/main.dart';
import 'package:arrivio_app/shared_destination.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('arrivio/shared_destination');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? nativePending;
  late SharedDestination shared;

  setUp(() {
    nativePending = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'takeSharedText') throw MissingPluginException();
      final result = nativePending;
      nativePending = null;
      return result;
    });
    shared = SharedDestination(channel: channel);
  });

  tearDown(() {
    shared.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> share(String text) async {
    nativePending = text;
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(const MethodCall('shareAvailable')),
      (_) => done.complete(),
    );
    await done.future;
  }

  testWidgets('cold share is held at login and filled after user login', (
    tester,
  ) async {
    nativePending = 'Example place\nhttps://maps.app.goo.gl/example';
    await shared.start();
    await tester.pumpWidget(MaterialApp(home: LoginPage(shared: shared)));
    expect(
      find.text('Destination received. Log in as a user to use it.'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          username: 'User',
          profile: const {},
          isMerchant: false,
          shared: shared,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.widgetWithText(TextField, 'https://maps.app.goo.gl/example'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Shared destination added. Select Set destination to continue.',
      ),
      findsOneWidget,
    );
    expect(find.text("What's the occasion?"), findsNothing);
    expect(shared.destination, isNull);
  });

  testWidgets('warm share fills the field and invalid text shows an error', (
    tester,
  ) async {
    await shared.start();
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          username: 'User',
          profile: const {},
          isMerchant: false,
          shared: shared,
        ),
      ),
    );
    await tester.pump();
    await share('Place\nhttps://maps.app.goo.gl/new');
    await tester.pump();
    expect(
      find.widgetWithText(TextField, 'https://maps.app.goo.gl/new'),
      findsOneWidget,
    );
    await share('text without a link');
    await tester.pump();
    expect(find.textContaining('does not contain a link'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'https://maps.app.goo.gl/new'),
      findsOneWidget,
    );
  });
}
