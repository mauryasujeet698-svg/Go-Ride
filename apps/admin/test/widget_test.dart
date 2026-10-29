import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride_admin/main.dart';

void main() {
  testWidgets('shows safe setup guidance when Supabase build config is missing', (tester) async {
    await tester.pumpWidget(const GoRideAdminApp());
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.textContaining('service-role key'), findsOneWidget);
  });
}
