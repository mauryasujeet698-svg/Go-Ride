import 'package:equatable/equatable.dart';

abstract class EntityId extends Equatable {
  final String value;
  EntityId(this.value) {
    if (value.trim().isEmpty) {
      throw ArgumentError('\${runtimeType.toString()} cannot be empty or whitespace.');
    }
  }
  @override
  List<Object> get props => [value];
}
class RideId extends EntityId { RideId(super.value); }
class UserId extends EntityId { UserId(super.value); }
class DriverId extends EntityId { DriverId(super.value); }
class VehicleId extends EntityId { VehicleId(super.value); }
class IntentId extends EntityId { IntentId(super.value); }
class EstimateId extends EntityId { EstimateId(super.value); }
class EventId extends EntityId { EventId(super.value); }
