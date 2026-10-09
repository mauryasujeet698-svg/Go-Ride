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
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Your trips'), findsOneWidget);
      expect(find.text('No trips yet'), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Guest rider'), findsOneWidget);
      expect(find.text('Help & support'), findsOneWidget);
    });
  });
}
