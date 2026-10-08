import 'dart:async';

import '../../core/error/failures.dart';
import '../../domain/entities/ride.dart';
import '../../domain/events/realtime_events.dart';
import '../../domain/events/telemetry.dart';
import '../../domain/state_machine/reconciliation.dart';
import '../../domain/services/i_auth_session_provider.dart';
import '../../domain/services/i_realtime_service.dart';
import '../usecases/ride_usecases.dart';

sealed class SyncState {\n  const SyncState();\n}

class SyncIdle extends SyncState {
  const SyncIdle();
}

class Syncing extends SyncState {
  const Syncing();
}

class SyncSuccess extends SyncState {
  final Ride ride;
  const SyncSuccess(this.ride);
}

class SyncFailed extends SyncState {
  final Failure failure;
  const SyncFailed(this.failure);
}

enum BufferProcessingResult { success, resyncRequired }

class RideSyncCoordinator {
  static const int _maxResyncAttempts = 3;

  final GetActiveRideUseCase _getActiveRide;
  final IRealtimeService _realtimeService;
  final IAuthSessionProvider _authProvider;
  final _stateController = StreamController<SyncState>.broadcast();
  final _telemetryController = StreamController<DriverTelemetry>.broadcast();
  final List<RideStateChanged> _eventBuffer = <RideStateChanged>[];

  bool _isFetchingSnapshot = false;
  bool _resyncRequested = false;
  Ride? _authoritativeRide;
  StreamSubscription<DomainRealtimeEvent>? _wsSubscription;

  RideSyncCoordinator(
    this._getActiveRide,
    this._realtimeService,
    this._authProvider,
  );

  Stream<SyncState> get syncStream => _stateController.stream;
  Stream<DriverTelemetry> get telemetryStream => _telemetryController.stream;
  Ride? get currentRide => _authoritativeRide;

  Future<void> startSync() async {
    if (_isFetchingSnapshot) {
      _resyncRequested = true;
      return;
    }

    _isFetchingSnapshot = true;
    _stateController.add(const Syncing());

    try {
      for (var attempt = 0; attempt < _maxResyncAttempts; attempt++) {
        _resyncRequested = false;

        final connected = await _ensureRealtimeConnection();
        if (!connected) return;

        final result = await _getActiveRide();
        var retryRequired = false;
        var terminal = false;

        await result.fold(
          (snapshot) async {
            if (snapshot == null) {
              _authoritativeRide = null;
              _eventBuffer.clear();
              _stateController.add(const SyncIdle());
              terminal = true;
              return;
            }

            _authoritativeRide = snapshot;

            final subscribeResult =
                await _realtimeService.subscribeToRide(snapshot.id);
            final subscribed = subscribeResult.fold(
              (_) => true,
              (failure) {
                _stateController.add(SyncFailed(failure));
                return false;
              },
            );

            if (!subscribed) {
              terminal = true;
              return;
            }

            final bufferResult = _processBuffer();
            if (bufferResult == BufferProcessingResult.resyncRequired) {
              retryRequired = true;
              return;
            }

            _stateController.add(SyncSuccess(_authoritativeRide!));
          },
          (failure) async {
            _stateController.add(SyncFailed(failure));
            terminal = true;
          },
        );

        if (terminal) return;
        if (_resyncRequested) retryRequired = true;
        if (!retryRequired) return;

        if (attempt == _maxResyncAttempts - 1) {
          _stateController.add(
            const SyncFailed(
              ReconciliationFailure(
                'Unable to reconcile the ride after bounded recovery attempts.',
              ),
            ),
          );
          return;
        }
      }
    } finally {
      _isFetchingSnapshot = false;
    }
  }

  Future<bool> _ensureRealtimeConnection() async {
    if (_wsSubscription != null) return true;

    final tokenResult = await _authProvider.getValidToken();
    return tokenResult.fold(
      (token) async {
        final connectResult =
            await _realtimeService.connectAuthenticated(token);
        return connectResult.fold(
          (_) {
            _wsSubscription =
                _realtimeService.eventStream.listen(_onRealtimeEvent);
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
    if (event is TelemetryUpdated) {
      if (_authoritativeRide?.id == event.telemetry.rideId) {
        _telemetryController.add(event.telemetry);
      }
      return;
    }

    if (event is! RideStateChanged) return;

    if (_isFetchingSnapshot) {
      if (_authoritativeRide == null ||
          event.incomingRide.id == _authoritativeRide!.id) {
        _eventBuffer.add(event);
      }
      return;
    }

    _reconcileLiveEvent(event);
  }

  BufferProcessingResult _processBuffer() {
    _eventBuffer.sort(
      (a, b) => a.incomingRide.version.compareTo(b.incomingRide.version),
    );

    var finalResult = BufferProcessingResult.success;
    for (final event in _eventBuffer) {
      if (_authoritativeRide == null ||
          event.incomingRide.id != _authoritativeRide!.id) {
        continue;
      }

      final result = RideReconciler.reconcile(
        local: _authoritativeRide!,
        incoming: event.incomingRide,
      );

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
    if (_authoritativeRide == null ||
        event.incomingRide.id != _authoritativeRide!.id) {
      return;
    }

    final result = RideReconciler.reconcile(
      local: _authoritativeRide!,
      incoming: event.incomingRide,
    );

    switch (result) {
      case ReconciliationResult.applied:
        _authoritativeRide = event.incomingRide;
        _stateController.add(SyncSuccess(_authoritativeRide!));
      case ReconciliationResult.stale:
      case ReconciliationResult.duplicate:
        break;
      case ReconciliationResult.gapDetected:
      case ReconciliationResult.invalidAuthoritativeState:
        _resyncRequested = true;
        if (!_isFetchingSnapshot) {
          unawaited(startSync());
        }
    }
  }

  Future<void> disconnect() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    _eventBuffer.clear();
    _resyncRequested = false;
    await _realtimeService.disconnect();
  }

  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _telemetryController.close();
  }
}
