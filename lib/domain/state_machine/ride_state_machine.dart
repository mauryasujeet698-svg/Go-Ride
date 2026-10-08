import '../enums/ride_status.dart';

class RideStateMachine {
  static const Map<RideStatus, List<RideStatus>> _validTransitions = {
    RideStatus.estimating: [RideStatus.searching, RideStatus.cancelled],
    RideStatus.searching: [RideStatus.driverAssigned, RideStatus.cancelling, RideStatus.cancelled],
    RideStatus.driverAssigned: [RideStatus.driverArriving, RideStatus.cancelling, RideStatus.cancelled],
    RideStatus.driverArriving: [RideStatus.driverArrived, RideStatus.cancelling, RideStatus.cancelled],
    RideStatus.driverArrived: [RideStatus.tripStarted, RideStatus.cancelling, RideStatus.cancelled],
    RideStatus.tripStarted: [RideStatus.tripInProgress],
    RideStatus.tripInProgress: [RideStatus.tripCompleted],
    RideStatus.cancelling: [RideStatus.cancelled, RideStatus.failed, RideStatus.driverAssigned],
    RideStatus.tripCompleted: [], RideStatus.cancelled: [], RideStatus.failed: [],
  };
  static bool canTransition(RideStatus current, RideStatus next) {
    if (current == next) return true;
    final allowed = _validTransitions[current];
    return allowed != null && allowed.contains(next);
  }
}
