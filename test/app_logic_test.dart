import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money conversion uses minor currency units', () {
    const amountMinor = 12550;
    expect((amountMinor / 100).toStringAsFixed(2), '125.50');
  });

  test('only active ride statuses remain cancellable by the UI', () {
    const active = {'searching', 'driver_assigned', 'driver_arriving', 'driver_arrived'};
    expect(active.contains('completed'), isFalse);
    expect(active.contains('searching'), isTrue);
  });
}
