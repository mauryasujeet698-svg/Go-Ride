import 'package:freezed_annotation/freezed_annotation.dart';
import '../../core/types/coordinate.dart';
part 'i_routing_provider.freezed.dart';

@freezed
abstract class RouteResult with _$RouteResult {
  const factory RouteResult({
    required List<Coordinate> polyline,
    required double distanceMeters,
    required int durationSeconds,
  }) = _RouteResult;
}

abstract class IRoutingProvider {
  Future<RouteResult> getRoute(Coordinate origin, Coordinate destination);
}
