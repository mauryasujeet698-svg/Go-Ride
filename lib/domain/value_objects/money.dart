import 'package:equatable/equatable.dart';

class Money extends Equatable {
  final int amountInMinorUnits;
  final String currencyCode;
  const Money._(this.amountInMinorUnits, this.currencyCode);
  factory Money.fromMinorUnits(int minorUnits, {String currencyCode = 'INR'}) =>
      Money._(minorUnits, currencyCode);
  factory Money.fromDecimalString(String value, {String currencyCode = 'INR'}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw ArgumentError('Money amount cannot be empty.');
    final regex = RegExp(r'^-?\d+(\.\d{1,2})?$');
    if (!regex.hasMatch(trimmed)) {
      throw ArgumentError('Invalid money format: $value. Must have at most 2 decimal places.');
    }
    final isNegative = trimmed.startsWith('-');
    final cleanString = isNegative ? trimmed.substring(1) : trimmed;
    final parts = cleanString.split('.');
    final major = int.parse(parts[0]);
    final minor = parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0;
    final total = (major * 100) + minor;
    return Money._(isNegative ? -total : total, currencyCode);
  }
  @override
  List<Object> get props => [amountInMinorUnits, currencyCode];
}
