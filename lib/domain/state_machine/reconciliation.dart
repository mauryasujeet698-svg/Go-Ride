import '../entities/ride.dart';
import 'ride_state_machine.dart';

enum ReconciliationResult { stale, duplicate, applied, gapDetected, invalidAuthoritativeState }

class RideReconciler {
  static ReconciliationResult reconcile({required Ride local, required Ride incoming}) {
    if (incoming.version < local.version) return ReconciliationResult.stale;
    if (incoming.version == local.version) return ReconciliationResult.duplicate;
    if (incoming.version == local.version + 1) {
      return RideStateMachine.canTransition(local.status, incoming.status)
          ? ReconciliationResult.applied
          : ReconciliationResult.invalidAuthoritativeState;
    }
    return ReconciliationResult.gapDetected;
  }
}
