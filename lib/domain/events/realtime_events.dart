import 'package:freezed_annotation/freezed_annotation.dart';
import '../entities/ride.dart';
import '../value_objects/identifiers.dart';
import 'telemetry.dart';
part 'realtime_events.freezed.dart';
@freezed
sealed class DomainRealtimeEvent with _$DomainRealtimeEvent {
  const factory DomainRealtimeEvent.rideStateChanged({
    required EventId eventId, required Ride incomingRide, required DateTime timestamp,
  }) = RideStateChanged;
  const factory DomainRealtimeEvent.telemetryUpdated({
    required EventId eventId, required DriverTelemetry telemetry,
  }) = TelemetryUpdated;
}
