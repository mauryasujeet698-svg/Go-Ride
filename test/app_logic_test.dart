import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride_customer/data/ride_backend.dart';
import 'package:go_ride_customer/main.dart';

void main() {
  test('fare quote parses integer minor units and expiry', () {
    final quote = FareQuote.fromMap({
      'quote_id': 'quote-1',
      'category': 'AUTO',
      'amount_minor': 5750,
      'currency': 'INR',
      'eta_seconds': 300,
      'expires_at': '2026-10-12T10:00:00Z',
    });
    expect(quote.id, 'quote-1');
    expect(quote.amountMinor, 5750);
    expect(quote.currency, 'INR');
    expect(quote.etaSeconds, 300);
    expect(quote.expiresAt.isUtc, isTrue);
  });

  test('ride record parses status, sequence and coordinates', () {
    final ride = RideRecord.fromMap({
      'id': 'ride-1',
      'status': 'searching',
      'seq': 1,
      'category': 'MINI',
      'fare_minor': 7200,
      'currency': 'INR',
      'pickup_lat': 12.9716,
      'pickup_lng': 77.5946,
      'destination_lat': 12.9352,
      'destination_lng': 77.6245,
      'created_at': '2026-10-12T10:00:00Z',
    });
    expect(ride.id, 'ride-1');
    expect(ride.status, 'searching');
    expect(ride.sequence, 1);
    expect(ride.pickup.latitude, closeTo(12.9716, 0.00001));
    expect(ride.destination.longitude, closeTo(77.6245, 0.00001));
  });

  test('currency values are formatted from minor units', () {
    const amountMinor = 12550;
    expect((amountMinor / 100).toStringAsFixed(2), '125.50');
  });

  testWidgets('guest can explore route planning without signing in', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: PreviewHomeScreen(backendReady: false)));
    expect(find.text('Where would you like to go?'), findsOneWidget);
    expect(find.text('Pickup location'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(find.text('Show route and fares'), findsOneWidget);
    expect(find.textContaining('without signing in'), findsOneWidget);
  });

  testWidgets('guest screen does not show demo ride confirmations', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: PreviewHomeScreen(backendReady: false)));
    expect(find.textContaining('Preview only'), findsNothing);
    expect(find.textContaining('no ride or payment will be created'), findsNothing);
    expect(find.text('Show route and fares'), findsOneWidget);
  });

}
