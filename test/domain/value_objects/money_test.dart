import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/domain/value_objects/money.dart';
void main() {
  test('parses decimal money exactly', () {
    expect(Money.fromDecimalString('150.25').amountInMinorUnits, 15025);
    expect(Money.fromDecimalString('150').amountInMinorUnits, 15000);
    expect(Money.fromDecimalString('-10.50').amountInMinorUnits, -1050);
  });
  test('rejects malformed precision', () {
    expect(() => Money.fromDecimalString('1.234'), throwsArgumentError);
    expect(() => Money.fromDecimalString(''), throwsArgumentError);
  });
}
