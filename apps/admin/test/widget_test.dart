import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride_admin/main.dart';

void main() {
  testWidgets('shows setup status and disconnected admin modules', (tester) async {
    await tester.pumpWidget(const GoRideAdminApp());
    expect(find.text('Operations console setup'), findsOneWidget);
    expect(find.text('Driver verification'), findsOneWidget);
    expect(find.text('Not connected'), findsWidgets);
  });
}
