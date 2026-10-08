import '../../core/result/result.dart';
import '../../core/error/failures.dart';
import '../../core/types/coordinate.dart';
import '../../domain/entities/ride.dart';
import '../../domain/entities/fare_estimate.dart';
import '../../domain/value_objects/identifiers.dart';
import '../../domain/repositories/i_ride_repository.dart';

class EstimateRideUseCase {
  final IRideRepository _repository;
  const EstimateRideUseCase(this._repository);
  Future<Result<FareEstimate, Failure>> call(Coordinate pickup, Coordinate dropoff) =>
      _repository.estimateFare(pickup, dropoff);
}
class RequestRideUseCase {
  final IRideRepository _repository;
  const RequestRideUseCase(this._repository);
  Future<Result<Ride, Failure>> call({
    required EstimateId estimateId, required IntentId intentId,
    required Coordinate pickup, required Coordinate dropoff,
  }) => _repository.requestRide(
    estimateId: estimateId, intentId: intentId, pickup: pickup, dropoff: dropoff);
}
class CancelRideUseCase {
  final IRideRepository _repository;
  const CancelRideUseCase(this._repository);
  Future<Result<Ride, Failure>> call(RideId rideId) => _repository.cancelRide(rideId);
}
class GetActiveRideUseCase {
  final IRideRepository _repository;
  const GetActiveRideUseCase(this._repository);
  Future<Result<Ride?, Failure>> call() => _repository.getActiveRide();
}
