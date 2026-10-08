import 'package:freezed_annotation/freezed_annotation.dart';
import '../../core/types/coordinate.dart';
import '../enums/ride_status.dart';
import '../value_objects/identifiers.dart';
import '../value_objects/money.dart';
import 'driver.dart';
part 'ride.freezed.dart';
@freezed
class Ride with _$Ride {
  const factory Ride({
    required RideId id, required UserId riderId, required IntentId idempotencyKey,
    required RideStatus status, required int version,
    required Coordinate pickupLocation, required Coordinate dropoffLocation,
    required Money estimatedFare, required DateTime createdAt, required DateTime updatedAt,
    Driver? assignedDriver, String? startOtp,
  }) = _Ride;
}
