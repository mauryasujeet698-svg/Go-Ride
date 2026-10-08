import 'dart:async';
import '../../core/error/failures.dart';
import '../../domain/entities/ride.dart';
import '../../domain/events/realtime_events.dart';
import '../../domain/state_machine/reconciliation.dart';
import '../../domain/services/i_auth_session_provider.dart';
import '../../domain/services/i_realtime_service.dart';
import '../usecases/ride_usecases.dart';

sealed class SyncState {}
class SyncIdle extends SyncState {}
class Syncing extends SyncState {}
class SyncSuccess extends SyncState { final Ride ride; SyncSuccess(this.ride); }
class SyncFailed extends SyncState { final Failure failure; SyncFailed(this.failure); }

enum BufferProcessingResult { success, resyncRequired }

class RideSyncCoordinator {
  final GetActiveRideUseCase _getActiveRide;
  final IRealtimeService _realtimeService;
  final IAuthSessionProvider _authProvider;
  final _stateController = StreamController<SyncState>.broadcast();
  final List<RideStateChanged> _eventBuffer = [];
  bool _isFetchingSnapshot = false;
  bool _resyncRequested = false;
  int _consecutiveResyncs = 0;
  Ride? _authoritativeRide;
  StreamSubscription? _wsSubscription;

  RideSyncCoordinator(this._getActiveRide, this._realtimeService, this._authProvider);
  Stream<SyncState> get syncStream => _stateController.stream;
  Ride? get currentRide => _authoritativeRide;

  Future<void> startSync() async {
    if (_isFetchingSnapshot) return;
    if (_consecutiveResyncs >= 3) {
      _stateController.add(SyncFailed(const ReconciliationFailure('Infinite resync loop detected.')));
      return;
    }
    _isFetchingSnapshot = true;
    _stateController.add(Syncing());

    final connSuccess = await _ensureRealtimeConnection();
    if (!connSuccess) {
      _isFetchingSnapshot = false;
      return;
    }

    final result = await _getActiveRide();
    await result.fold(
      (snapshot) async {
        if (snapshot != null) {
          _authoritativeRide = snapshot;
          await _realtimeService.subscribeToRide(snapshot.id);
          final bufferResult = _processBuffer();
          if (bufferResult == BufferProcessingResult.resyncRequired) {
            _isFetchingSnapshot = false;
            _consecutiveResyncs++;
            await startSync();
          } else {
            _consecutiveResyncs = 0;
            _stateController.add(SyncSuccess(_authoritativeRide!));
          }
        } else {
          _authoritativeRide = null;
          _eventBuffer.clear();
          _consecutiveResyncs = 0;
          _stateController.add(SyncIdle());
        }
      },
      (failure) async {
        _stateController.add(SyncFailed(failure));
      },
    );

    _isFetchingSnapshot = false;
    if (_resyncRequested) {
      _resyncRequested = false;
      await startSync();
    }
  }

  Future<bool> _ensureRealtimeConnection() async {
    if (_wsSubscription != null) return true;
    final tokenResult = await _authProvider.getValidToken();
    return tokenResult.fold(
      (token) async {
        final connectResult = await _realtimeService.connectAuthenticated(token);
        return connectResult.fold(
          (_) {
            _wsSubscription = _realtimeService.eventStream.listen(_onRealtimeEvent);
            return true;
          },
          (failure) {
            _stateController.add(SyncFailed(failure));
            return false;
          },
        );
      },
      (failure) async {
        _stateController.add(SyncFailed(failure));
        return false;
      },
    );
  }

  void _onRealtimeEvent(DomainRealtimeEvent event) {
    if (event is! RideStateChanged) return;
    if (_isFetchingSnapshot) {
      _eventBuffer.add(event);
    } else {
      _reconcileLiveEvent(event);
    }
  }

  BufferProcessingResult _processBuffer() {
    _eventBuffer.sort((a, b) => a.incomingRide.version.compareTo(b.incomingRide.version));
    var finalResult = BufferProcessingResult.success;
    for (final event in _eventBuffer) {
      if (_authoritativeRide == null || event.incomingRide.id != _authoritativeRide!.id) continue;
      final result = RideReconciler.reconcile(local: _authoritativeRide!, incoming: event.incomingRide);
      switch (result) {
        case ReconciliationResult.applied:
          _authoritativeRide = event.incomingRide;
        case ReconciliationResult.stale:
        case ReconciliationResult.duplicate:
          break;
        case ReconciliationResult.gapDetected:
        case ReconciliationResult.invalidAuthoritativeState:
          finalResult = BufferProcessingResult.resyncRequired;
          break;
      }
      if (finalResult == BufferProcessingResult.resyncRequired) break;
    }
    _eventBuffer.clear();
    return finalResult;
  }

  void _reconcileLiveEvent(RideStateChanged event) {
    if (_authoritativeRide == null || event.incomingRide.id != _authoritativeRide!.id) return;
    final result = RideReconciler.reconcile(local: _authoritativeRide!, incoming: event.incomingRide);
    switch (result) {
      case ReconciliationResult.applied:
        _authoritativeRide = event.incomingRide;
        _consecutiveResyncs = 0;
        _stateController.add(SyncSuccess(_authoritativeRide!));
      case ReconciliationResult.stale:
      case ReconciliationResult.duplicate:
        break;
      case ReconciliationResult.gapDetected:
      case ReconciliationResult.invalidAuthoritativeState:
        _consecutiveResyncs++;
        _resyncRequested = true;
        if (!_isFetchingSnapshot) startSync();
    }
  }

  Future<void> disconnect() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _realtimeService.disconnect();
  }

  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
  }
}
