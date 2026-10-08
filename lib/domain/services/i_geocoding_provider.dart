import '../../core/types/coordinate.dart';
import 'i_places_provider.dart';

abstract class IGeocodingProvider {
  Future<PlaceResult> reverseGeocode(Coordinate coordinate);
}
