import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:uuid/uuid.dart';
import 'ride_event.dart';
import 'ride_state.dart';
import '../../../core/error/failures.dart';
import '../../../core/retry/retry_policy.dart';
import '../../../domain/value_objects/identifiers.dart';
import '../../../domain/enums/ride_status.dart';
import '../../../application/usecases/ride_usecases.dart';
import '../../../application/sync/ride_sync_coordinator.dart';

class RideBloc extends Bloc<RideEvent, RideState> {
  final EstimateRideUseCase _estimateRide;
  final RequestRideUseCase _requestRide;
  final CancelRideUseCase _cancelRide;
  final RideSyncCoordinator _syncCoordinator;
  StreamSubscription? _syncSubscription;

  RideBloc({
    required EstimateRideUseCase estimateRide,
    required RequestRideUseCase requestRide,
    required CancelRideUseCase cancelRide,
    required RideSyncCoordinator syncCoordinator,
  }) : _estimateRide = estimateRide,
       _requestRide = requestRide,
       _cancelRide = cancelRide,
       _syncCoordinator = syncCoordinator,
       super(RideState.initial()) {
    on<EstimateRequested>(_onEstimateRequested, transformer: restartable());
    on<BookingConfirmed>(_onBookingConfirmed, transformer: droppable());
    on<CancellationRequested>(_onCancellationRequested, transformer: droppable());
    on<SyncStateUpdated>(_onSyncStateUpdated, transformer: sequential());
    on<TelemetryReceived>(_onTelemetryReceived, transformer: sequential());
    on<AppForegrounded>(_onAppForegrounded, transformer: droppable());
    on<AppBackgrounded>(_onAppBackgrounded);
    _syncSubscription = _syncCoordinator.syncStream.listen((syncState) {
      add(SyncStateUpdated(syncState));
    });
  }

  Future<void> _onEstimateRequested(EstimateRequested event, Emitter<RideState> emit) async {
    final requestId = const Uuid().v4();
    emit(state.copyWith(uiStatus: RideUiStatus.estimating, failure: null,
      activeEstimateRequestId: requestId, activePickup: event.pickup,
      activeDropoff: event.dropoff, currentEstimate: null));
    final result = await _estimateRide(event.pickup, event.dropoff);
    if (state.activeEstimateRequestId != requestId) return;
    result.fold(
      (estimate) => emit(state.copyWith(uiStatus: RideUiStatus.readyToConfirm, currentEstimate: estimate)),
      (failure) => emit(state.copyWith(uiStatus: RideUiStatus.error, failure: failure)),
    );
  }

  Future<void> _onBookingConfirmed(BookingConfirmed event, Emitter<RideState> emit) async {
    if (state.currentEstimate == null || state.activePickup == null || state.activeDropoff == null) return;
    final intentId = state.activeIntentId ?? IntentId(const Uuid().v4());
    emit(state.copyWith(uiStatus: RideUiStatus.submitting, activeIntentId: intentId, failure: null));
    final result = await RetryPolicy.execute(() => _requestRide(
      estimateId: state.currentEstimate!.id, intentId: intentId,
      pickup: state.activePickup!, dropoff: state.activeDropoff!));
    result.fold(
      (ride) {
        emit(state.copyWith(uiStatus: _mapDomainStatusToUi(ride.status), authoritativeRide: ride, activeIntentId: null));
        _syncCoordinator.startSync();
      },
      (failure) => emit(state.copyWith(uiStatus: RideUiStatus.error, failure: failure)),
    );
  }

  Future<void> _onCancellationRequested(CancellationRequested event, Emitter<RideState> emit) async {
    if (state.authoritativeRide == null) return;
    emit(state.copyWith(uiStatus: RideUiStatus.cancelling));
    final result = await _cancelRide(state.authoritativeRide!.id);
    result.fold(
      (ride) => emit(state.copyWith(uiStatus: _mapDomainStatusToUi(ride.status), authoritativeRide: ride)),
      (failure) {
        if (failure is ConflictFailure) {
          emit(state.copyWith(uiStatus: RideUiStatus.recovering, failure: null));
          _syncCoordinator.startSync();
        } else {
          emit(state.copyWith(uiStatus: RideUiStatus.error, failure: failure));
        }
      },
    );
  }

  void _onSyncStateUpdated(SyncStateUpdated event, Emitter<RideState> emit) {
    final s = event.state;
    if (s is Syncing) emit(state.copyWith(uiStatus: RideUiStatus.recovering, failure: null));
    if (s is SyncSuccess) emit(state.copyWith(uiStatus: _mapDomainStatusToUi(s.ride.status), authoritativeRide: s.ride));
    if (s is SyncFailed) emit(state.copyWith(uiStatus: RideUiStatus.error, failure: s.failure));
    if (s is SyncIdle) emit(state.copyWith(uiStatus: RideUiStatus.initial, authoritativeRide: null));
  }

  void _onTelemetryReceived(TelemetryReceived event, Emitter<RideState> emit) {
    if (state.authoritativeRide?.id != event.telemetry.rideId) return;
    if (event.telemetry.isFresh(DateTime.now())) emit(state.copyWith(telemetry: event.telemetry));
  }

  Future<void> _onAppForegrounded(AppForegrounded event, Emitter<RideState> emit) async {
    await _syncCoordinator.startSync();
  }

  Future<void> _onAppBackgrounded(AppBackgrounded event, Emitter<RideState> emit) async {
    await _syncCoordinator.disconnect();
  }

  RideUiStatus _mapDomainStatusToUi(RideStatus status) {
    switch (status) {
      case RideStatus.searching: return RideUiStatus.searching;
      case RideStatus.driverAssigned: return RideUiStatus.driverAssigned;
      case RideStatus.driverArriving: return RideUiStatus.driverArrived;
      case RideStatus.driverArrived: return RideUiStatus.driverArrived;
      case RideStatus.tripStarted:
      case RideStatus.tripInProgress: return RideUiStatus.inTrip;
      case RideStatus.cancelling: return RideUiStatus.cancelling;
      case RideStatus.cancelled: return RideUiStatus.cancelled;
      case RideStatus.failed: return RideUiStatus.error;
      case RideStatus.estimating:
      case RideStatus.tripCompleted: return RideUiStatus.initial;
    }
  }

  @override
  Future<void> close() async {
    await _syncSubscription?.cancel();
    await _syncCoordinator.dispose();
    return super.close();
  }
}
