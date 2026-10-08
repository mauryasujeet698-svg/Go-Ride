import 'package:equatable/equatable.dart';

class Coordinate extends Equatable {
  final double latitude;
  final double longitude;
  const Coordinate._(this.latitude, this.longitude);
  factory Coordinate({required double latitude, required double longitude}) {
    if (latitude.isNaN || longitude.isNaN || latitude.isInfinite || longitude.isInfinite) {
      throw ArgumentError('Coordinates cannot be NaN or Infinite.');
    }
    if (latitude < -90.0 || latitude > 90.0) throw ArgumentError('Latitude must be between -90 and 90.');
    if (longitude < -180.0 || longitude > 180.0) throw ArgumentError('Longitude must be between -180 and 180.');
    return Coordinate._(latitude, longitude);
  }
  @override
  List<Object> get props => [latitude, longitude];
}
