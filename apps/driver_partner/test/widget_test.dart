import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride_driver_partner/main.dart';

void main() {
  testWidgets('shows honest setup status and unavailable live features', (tester) async {
    await tester.pumpWidget(const DriverPartnerApp());
    expect(find.text('Setup in progress'), findsOneWidget);
    expect(find.text('Ride offers'), findsOneWidget);
    expect(find.textContaining('No fake online status or earnings are shown.'), findsOneWidget);
  });
}
