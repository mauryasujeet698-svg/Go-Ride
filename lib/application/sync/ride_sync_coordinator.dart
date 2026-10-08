          retryRequired = true;
        }

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
      _eventBuffer.add(event);
    } else {
      _reconcileLiveEvent(event);
    }
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