import '../../core/types/coordinate.dart';

class PlaceResult {
  final String address;
  final Coordinate coordinate;
  const PlaceResult({required this.address, required this.coordinate});
}

abstract class IPlacesProvider {
  Future<List<PlaceResult>> searchPlaces(String query);
}
