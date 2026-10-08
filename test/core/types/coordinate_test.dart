import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/core/types/coordinate.dart';
void main() {
  test('rejects invalid latitude/longitude', () {
    expect(() => Coordinate(latitude: 91, longitude: 0), throwsArgumentError);
    expect(() => Coordinate(latitude: 0, longitude: 181), throwsArgumentError);
  });
  test('accepts boundaries', () {
    final c = Coordinate(latitude: 90, longitude: 180);
    expect(c.latitude, 90);
    expect(c.longitude, 180);
  });
}
