import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/types/coordinate.dart';
import '../value_objects/identifiers.dart';

part 'telemetry.freezed.dart';

@freezed
class DriverTelemetry with _$DriverTelemetry {
  const DriverTelemetry._();

  const factory DriverTelemetry({
    required DriverId driverId,
    required RideId rideId,
    required Coordinate location,
    required double bearing,
    required DateTime timestamp,
  }) = _DriverTelemetry;

  bool isFresh(
    DateTime currentTime, {
    Duration maxAge = const Duration(seconds: 15),
    Duration clockSkewTolerance = const Duration(seconds: 30),
  }) {
    final age = currentTime.difference(timestamp);
    if (age < -clockSkewTolerance) return false;
    return age <= maxAge;
  }
}
