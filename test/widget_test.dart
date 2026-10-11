import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/main.dart';

void main() {
  group('Go-Ride customer app smoke tests', () {
    testWidgets('shows the ride-booking home screen', (tester) async {
      await tester.pumpWidget(const GoRideApp());
      await tester.pump();

      expect(find.text('Go-Ride'), findsOneWidget);
      expect(find.text('Where are you going?'), findsOneWidget);
      expect(find.text('Choose pickup and destination on map'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Trips'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('bottom navigation opens Trips and Profile', (tester) async {
      await tester.pumpWidget(const GoRideApp());
      await tester.pump();

      await tester.tap(find.text('Trips'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Your trips'), findsOneWidget);
      expect(find.text('No trips yet'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Profile').first, findsOneWidget);
      expect(find.text('Guest rider'), findsOneWidget);
      expect(find.text('Help & support'), findsOneWidget);
    });

    testWidgets('notifications and support open honest preview screens', (tester) async {
      await tester.pumpWidget(const GoRideApp());
      await tester.pump();

      await tester.tap(find.text('Profile'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Help & support'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Quick help'), findsOneWidget);
      expect(find.text('Is the shown fare final?'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Sign in / create account'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Welcome back'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Enter a valid 10-digit Indian mobile number.'), findsOneWidget);
      await tester.tap(find.text('New to Go-Ride? Create account'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Full name'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Home'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('No notifications yet'), findsOneWidget);
      expect(find.textContaining('does not send or receive live alerts'), findsOneWidget);
    });

    testWidgets('requires both locations before opening ride review', (tester) async {
      await tester.pumpWidget(const GoRideApp());
      await tester.pump();

      await _scrollHomeToBottom(tester);
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(find.text('Please enter both pickup and destination.'), findsOneWidget);
      expect(find.text('Review ride'), findsNothing);
    });

    testWidgets('labels the local request as a demo, not a live booking', (tester) async {
      await tester.pumpWidget(const GoRideApp());
      await tester.pump();

      await tester.enterText(find.widgetWithText(TextField, 'Pickup location'), 'Prayagraj Station');
      await tester.enterText(find.widgetWithText(TextField, 'Destination'), 'Civil Lines');
      await _scrollHomeToBottom(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('Review ride'), findsOneWidget);
      expect(find.text('Illustrative demo fare'), findsOneWidget);
      await tester.tap(find.text('Preview request flow'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('Demo request created'), findsOneWidget);
      expect(find.text('No driver was contacted. Real ride requests require the backend, driver app and dispatch service.'), findsOneWidget);
    });
  });
}


Future<void> _scrollHomeToBottom(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final scrollableFinder = find.descendant(
    of: find.byType(CustomScrollView).first,
    matching: find.byType(Scrollable),
  );
  final scrollable = tester.state<ScrollableState>(scrollableFinder.first);
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
}
