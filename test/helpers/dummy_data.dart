import 'package:go_ride/core/types/coordinate.dart';
import 'package:go_ride/domain/value_objects/identifiers.dart';
import 'package:go_ride/domain/value_objects/money.dart';
import 'package:go_ride/domain/enums/ride_status.dart';
import 'package:go_ride/domain/entities/vehicle.dart';
import 'package:go_ride/domain/entities/driver.dart';
import 'package:go_ride/domain/entities/fare_estimate.dart';
import 'package:go_ride/domain/entities/ride.dart';
import 'package:go_ride/domain/events/telemetry.dart';

final tCoordinatePickup = Coordinate(latitude: 12.9716, longitude: 77.5946);
final tCoordinateDropoff = Coordinate(latitude: 12.2958, longitude: 76.6394);
final tMoney = Money.fromMinorUnits(15000);
final tEstimateId = EstimateId('est_123');
final tIntentId = IntentId('intent_123');
final tRideId = RideId('ride_123');
final tUserId = UserId('user_123');
final tDriverId = DriverId('driver_123');
final tVehicleId = VehicleId('vehicle_123');
final tEventId = EventId('event_123');
final tFareEstimate = FareEstimate(id: tEstimateId, amount: tMoney, distanceMeters: 5000.0);
final tVehicle = Vehicle(id: tVehicleId, make: 'Bajaj', model: 'RE', licensePlate: 'KA-01-AB-1234', color: 'Yellow');
final tDriver = Driver(id: tDriverId, firstName: 'Kumar', aggregateRating: 4.8, vehicle: tVehicle);
final tRide = Ride(
  id: tRideId, riderId: tUserId, idempotencyKey: tIntentId, status: RideStatus.searching, version: 1,
  pickupLocation: tCoordinatePickup, dropoffLocation: tCoordinateDropoff, estimatedFare: tMoney,
  createdAt: DateTime(2026, 1, 1, 12), updatedAt: DateTime(2026, 1, 1, 12),
);
final tDriverTelemetry = DriverTelemetry(
  driverId: tDriverId, rideId: tRideId, location: tCoordinatePickup, bearing: 90, timestamp: DateTime.now(),
);
