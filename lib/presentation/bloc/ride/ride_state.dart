import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/error/failures.dart';
import '../../../core/types/coordinate.dart';
import '../../../domain/entities/ride.dart';
import '../../../domain/entities/fare_estimate.dart';
import '../../../domain/events/telemetry.dart';
import '../../../domain/value_objects/identifiers.dart';

part 'ride_state.freezed.dart';

enum RideUiStatus {
  initial,
  estimating,
  readyToConfirm,
  submitting,
  searching,
  driverAssigned,
  driverArriving,
  driverArrived,
  inTrip,
  cancelling,
  recovering,
  cancelled,
  error,
}

@freezed
abstract class RideState with _$RideState {
  const factory RideState({
    required RideUiStatus uiStatus,
    Ride? authoritativeRide,
    FareEstimate? currentEstimate,
    Coordinate? activePickup,
    Coordinate? activeDropoff,
    String? activeEstimateRequestId,
    IntentId? activeIntentId,
    DriverTelemetry? telemetry,
    Failure? failure,
  }) = _RideState;

  factory RideState.initial() =>
      const RideState(uiStatus: RideUiStatus.initial);
}
