import 'package:freezed_annotation/freezed_annotation.dart';
import '../value_objects/identifiers.dart';
part 'vehicle.freezed.dart';
@freezed
class Vehicle with _$Vehicle {
  const factory Vehicle({
    required VehicleId id, required String make, required String model,
    required String licensePlate, required String color,
  }) = _Vehicle;
}
