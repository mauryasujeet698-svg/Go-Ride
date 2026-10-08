import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/types/coordinate.dart';
import '../../../domain/events/telemetry.dart';
import '../../../application/sync/ride_sync_coordinator.dart';
part 'ride_event.freezed.dart';

@freezed
class RideEvent with _$RideEvent {
  const factory RideEvent.estimateRequested(Coordinate pickup, Coordinate dropoff) = EstimateRequested;
  const factory RideEvent.bookingConfirmed() = BookingConfirmed;
  const factory RideEvent.cancellationRequested() = CancellationRequested;
  const factory RideEvent.telemetryReceived(DriverTelemetry telemetry) = TelemetryReceived;
  const factory RideEvent.syncStateUpdated(SyncState state) = SyncStateUpdated;
  const factory RideEvent.appForegrounded() = AppForegrounded;
  const factory RideEvent.appBackgrounded() = AppBackgrounded;
}
