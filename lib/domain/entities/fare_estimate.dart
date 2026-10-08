import 'package:freezed_annotation/freezed_annotation.dart';
import '../value_objects/identifiers.dart';
import '../value_objects/money.dart';
part 'fare_estimate.freezed.dart';
@freezed
class FareEstimate with _$FareEstimate {
  const factory FareEstimate({
    required EstimateId id, required Money amount, required double distanceMeters,
  }) = _FareEstimate;
}
