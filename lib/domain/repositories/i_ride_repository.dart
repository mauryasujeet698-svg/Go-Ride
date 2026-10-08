import '../../core/error/failures.dart';
import '../../core/result/result.dart';
import '../../core/types/coordinate.dart';
import '../entities/fare_estimate.dart';
import '../entities/ride.dart';
import '../value_objects/identifiers.dart';

abstract class IRideRepository {
  Future<Result<FareEstimate, Failure>> estimateFare(Coordinate pickup, Coordinate dropoff);
  Future<Result<Ride, Failure>> requestRide({
    required IntentId intentId, required EstimateId estimateId,
    required Coordinate pickup, required Coordinate dropoff,
  });
  Future<Result<Ride?, Failure>> getActiveRide();
  Future<Result<Ride, Failure>> cancelRide(RideId rideId);
}
