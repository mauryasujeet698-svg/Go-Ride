import '../../core/error/failures.dart';
import '../../core/result/result.dart';
import '../events/realtime_events.dart';
import '../value_objects/identifiers.dart';

abstract class IRealtimeService {
  Future<Result<void, Failure>> connectAuthenticated(String token);
  Future<void> disconnect();
  Future<Result<void, Failure>> subscribeToRide(RideId rideId);
  Stream<DomainRealtimeEvent> get eventStream;
}
