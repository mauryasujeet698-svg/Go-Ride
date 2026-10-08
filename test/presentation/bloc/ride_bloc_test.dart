import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_ride/core/error/failures.dart';
import 'package:go_ride/core/result/result.dart';
import 'package:go_ride/domain/enums/ride_status.dart';
import 'package:go_ride/application/sync/ride_sync_coordinator.dart';
import 'package:go_ride/presentation/bloc/ride/ride_bloc.dart';
import 'package:go_ride/presentation/bloc/ride/ride_event.dart';
import 'package:go_ride/presentation/bloc/ride/ride_state.dart';
import '../../helpers/dummy_data.dart';
import '../../helpers/test_setup.dart';

void main() {
  late MockEstimateRideUseCase estimate;
  late MockRequestRideUseCase request;
  late MockCancelRideUseCase cancel;
  late MockRideSyncCoordinator sync;
  late StreamController<SyncState> syncStates;
  late RideBloc bloc;

  setUp(() {
    registerFallbackValues();
    estimate = MockEstimateRideUseCase();
    request = MockRequestRideUseCase();
    cancel = MockCancelRideUseCase();
    sync = MockRideSyncCoordinator();
    syncStates = StreamController<SyncState>.broadcast();
    when(() => sync.syncStream).thenAnswer((_) => syncStates.stream);
    when(() => sync.telemetryStream).thenAnswer((_) => const Stream<DriverTelemetry>.empty());
    when(() => sync.startSync()).thenAnswer((_) async {});
    when(() => sync.disconnect()).thenAnswer((_) async {});
    when(() => sync.dispose()).thenAnswer((_) async {});
    bloc = RideBloc(estimateRide: estimate, requestRide: request, cancelRide: cancel, syncCoordinator: sync);
  });

  tearDown(() async {
    await bloc.close();
    await syncStates.close();
  });

  blocTest<RideBloc, RideState>(
    '409 cancellation conflict enters recovery and resyncs',
    build: () {
      when(() => cancel(any())).thenAnswer((_) async => const Error(ConflictFailure('Driver matched')));
      return bloc;
    },
    seed: () => RideState(uiStatus: RideUiStatus.searching, authoritativeRide: tRide),
    act: (b) async {
      b.add(const CancellationRequested());
      await Future<void>.delayed(Duration.zero);
      b.add(SyncStateUpdated(SyncSuccess(tRide.copyWith(status: RideStatus.driverAssigned))));
    },
    expect: () => [
      isA<RideState>().having((s) => s.uiStatus, 'status', RideUiStatus.cancelling),
      isA<RideState>().having((s) => s.uiStatus, 'status', RideUiStatus.recovering),
      isA<RideState>().having((s) => s.uiStatus, 'status', RideUiStatus.driverAssigned),
    ],
    verify: (_) => verify(() => sync.startSync()).called(1),
  );
}
