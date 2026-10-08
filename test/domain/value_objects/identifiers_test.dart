import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/domain/value_objects/identifiers.dart';
void main() {
  test('rejects empty/whitespace IDs', () {
    expect(() => RideId(''), throwsArgumentError);
    expect(() => RideId('   '), throwsArgumentError);
  });
  test('equal IDs compare equal', () {
    expect(RideId('uuid-123'), RideId('uuid-123'));
  });
}
