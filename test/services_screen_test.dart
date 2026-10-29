import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride_customer/main.dart';

void main() {
  testWidgets('Services screen lists available and upcoming services', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ServicesScreen()));

    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Ride Booking'), findsOneWidget);
    expect(find.text('Parcel Delivery'), findsOneWidget);
    expect(find.text('Food Delivery'), findsOneWidget);
    expect(find.text('Shopping & Quick Commerce'), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(2));
  });

  testWidgets('Home Services navigation opens the Services screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PreviewHomeScreen(backendReady: false),
    ));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pump();

    expect(find.byType(ServicesScreen), findsOneWidget);
    expect(find.text('Choose a service'), findsOneWidget);
  });

  testWidgets('Parcel service opens the parcel screen', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ServicesScreen()),
            ),
            child: const Text('Open services'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parcel Delivery'));
    await tester.pumpAndSettle();

    expect(find.text('Parcel'), findsOneWidget);
    expect(find.text('Send Parcel'), findsOneWidget);
  });
}
