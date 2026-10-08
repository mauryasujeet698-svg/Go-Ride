import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/domain/state_machine/reconciliation.dart';
import 'package:go_ride/domain/enums/ride_status.dart';
import '../../helpers/dummy_data.dart';

void main() {
  test('classifies stale, duplicate and gap', () {
    expect(RideReconciler.reconcile(local: tRide.copyWith(version: 10), incoming: tRide.copyWith(version: 9)), ReconciliationResult.stale);
    expect(RideReconciler.reconcile(local: tRide.copyWith(version: 10), incoming: tRide.copyWith(version: 10)), ReconciliationResult.duplicate);
    expect(RideReconciler.reconcile(local: tRide.copyWith(version: 10), incoming: tRide.copyWith(version: 12)), ReconciliationResult.gapDetected);
  });
  test('accepts valid sequential transition', () {
    expect(RideReconciler.reconcile(
      local: tRide.copyWith(version: 10, status: RideStatus.searching),
      incoming: tRide.copyWith(version: 11, status: RideStatus.driverAssigned),
    ), ReconciliationResult.applied);
  });
  test('rejects invalid sequential transition', () {
    expect(RideReconciler.reconcile(
      local: tRide.copyWith(version: 10, status: RideStatus.searching),
      incoming: tRide.copyWith(version: 11, status: RideStatus.tripCompleted),
    ), ReconciliationResult.invalidAuthoritativeState);
  });
}
