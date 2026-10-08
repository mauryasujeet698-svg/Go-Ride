import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/domain/enums/ride_status.dart';
import 'package:go_ride/domain/state_machine/ride_state_machine.dart';
void main() {
  test('valid transitions', () {
    expect(RideStateMachine.canTransition(RideStatus.searching, RideStatus.driverAssigned), isTrue);
    expect(RideStateMachine.canTransition(RideStatus.driverAssigned, RideStatus.driverArriving), isTrue);
    expect(RideStateMachine.canTransition(RideStatus.searching, RideStatus.cancelling), isTrue);
  });
  test('invalid and terminal transitions', () {
    expect(RideStateMachine.canTransition(RideStatus.searching, RideStatus.tripCompleted), isFalse);
    expect(RideStateMachine.canTransition(RideStatus.cancelled, RideStatus.searching), isFalse);
  });
}
