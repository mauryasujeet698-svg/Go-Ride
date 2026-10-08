import 'package:mocktail/mocktail.dart';
import 'package:go_ride/core/types/coordinate.dart';
import 'package:go_ride/domain/value_objects/identifiers.dart';
import 'package:go_ride/domain/repositories/i_ride_repository.dart';
import 'package:go_ride/domain/services/i_auth_session_provider.dart';
import 'package:go_ride/domain/services/i_realtime_service.dart';
import 'package:go_ride/application/usecases/ride_usecases.dart';
import 'package:go_ride/application/sync/ride_sync_coordinator.dart';

class MockRideRepository extends Mock implements IRideRepository {}
class MockRealtimeService extends Mock implements IRealtimeService {}
class MockAuthSessionProvider extends Mock implements IAuthSessionProvider {}
class MockEstimateRideUseCase extends Mock implements EstimateRideUseCase {}
class MockRequestRideUseCase extends Mock implements RequestRideUseCase {}
class MockCancelRideUseCase extends Mock implements CancelRideUseCase {}
class MockGetActiveRideUseCase extends Mock implements GetActiveRideUseCase {}
class MockRideSyncCoordinator extends Mock implements RideSyncCoordinator {}

void registerFallbackValues() {
  registerFallbackValue(Coordinate(latitude: 0, longitude: 0));
  registerFallbackValue(EstimateId('fallback_est'));
  registerFallbackValue(IntentId('fallback_intent'));
  registerFallbackValue(RideId('fallback_ride'));
}
