import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_ride/core/error/failures.dart';
import 'package:go_ride/core/result/result.dart';
import 'package:go_ride/domain/enums/ride_status.dart';
import 'package:go_ride/domain/events/realtime_events.dart';
import 'package:go_ride/application/sync/ride_sync_coordinator.dart';
import '../../helpers/dummy_data.dart';
import '../../helpers/test_setup.dart';
import 'package:go_ride/domain/entities/ride.dart';

void main() {
  late RideSyncCoordinator coordinator;
  late MockGetActiveRideUseCase getActiveRide;
  late MockRealtimeService realtime;
  late MockAuthSessionProvider auth;
  late StreamController<DomainRealtimeEvent> stream;
  late List<SyncState> states;
  late StreamSubscription subscription;

  setUp(() {
    registerFallbackValues();
    getActiveRide = MockGetActiveRideUseCase();
    realtime = MockRealtimeService();
    auth = MockAuthSessionProvider();
    stream = StreamController<DomainRealtimeEvent>.broadcast();
    states = [];
    when(() => auth.getValidToken()).thenAnswer((_) async => const Success<String, Failure>('token'));
    when(() => realtime.connectAuthenticated(any())).thenAnswer((_) async => const Success<void, Failure>(null));
    when(() => realtime.eventStream).thenReturn(stream.stream);
    when(() => realtime.subscribeToRide(any())).thenAnswer((_) async => const Success<void, Failure>(null));
    when(() => realtime.disconnect()).thenAnswer((_) async {});
    coordinator = RideSyncCoordinator(getActiveRide, realtime, auth);
    subscription = coordinator.syncStream.listen(states.add);
  });

  tearDown(() async {
    await subscription.cancel();
    await coordinator.dispose();
  });

  test('applies buffered N+1 event after REST baseline', () async {
    final completer = Completer<Result<Ride?, Failure>>();
    when(() => getActiveRide()).thenAnswer((_) => completer.future);
    final future = coordinator.startSync();
    await Future<void>.delayed(Duration.zero);
    stream.add(RideStateChanged(eventId: tEventId, timestamp: DateTime.now(), incomingRide: tRide.copyWith(version: 2, status: RideStatus.driverAssigned)));
    completer.complete(Success<Ride?, Failure>(tRide));
    await future;
    final successes = states.whereType<SyncSuccess>().toList();
    expect(successes.single.ride.version, 2);
  });

  test('auth failure prevents REST access', () async {
    when(() => auth.getValidToken()).thenAnswer((_) async => const Error<String, Failure>(AuthFailure('No token')));
    await coordinator.startSync();
    expect(states.last, isA<SyncFailed>());
    verifyNever(() => getActiveRide());
  });
}
