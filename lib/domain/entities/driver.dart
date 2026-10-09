import 'package:freezed_annotation/freezed_annotation.dart';
import '../value_objects/identifiers.dart';
import 'vehicle.dart';
part 'driver.freezed.dart';
@freezed
abstract class Driver with _$Driver {
  const factory Driver({
    required DriverId id, required String firstName,
    required double aggregateRating, required Vehicle vehicle,
  }) = _Driver;
}
