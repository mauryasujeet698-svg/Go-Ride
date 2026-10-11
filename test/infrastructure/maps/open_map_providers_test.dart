import 'package:flutter_test/flutter_test.dart';
import 'package:go_ride/infrastructure/maps/open_map_providers.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('RoadRoute', () {
    test('formats distance in kilometres and minutes', () {
      const route = RoadRoute(
        points: [LatLng(26.8, 80.9), LatLng(26.9, 81.0)],
        distanceMeters: 12450,
        durationSeconds: 1560,
      );

      expect(route.distanceLabel, '12.5 km');
      expect(route.durationLabel, '≈ 26 min');
    });

    test('formats short routes in metres and long routes in hours', () {
      const shortRoute = RoadRoute(
        points: [LatLng(26.8, 80.9), LatLng(26.81, 80.91)],
        distanceMeters: 850,
        durationSeconds: 900,
      );
      const longRoute = RoadRoute(
        points: [LatLng(26.8, 80.9), LatLng(27.8, 81.9)],
        distanceMeters: 125000,
        durationSeconds: 5460,
      );

      expect(shortRoute.distanceLabel, '850 m');
      expect(shortRoute.durationLabel, '≈ 15 min');
      expect(longRoute.distanceLabel, '125.0 km');
      expect(longRoute.durationLabel, '≈ 1h 31m');
    });
  });

  group('PlaceSearchResult', () {
    test('retains the human-readable label and coordinate', () {
      const result = PlaceSearchResult(
        label: 'Prayagraj Junction',
        point: LatLng(25.4358, 81.8463),
      );

      expect(result.label, 'Prayagraj Junction');
      expect(result.point.latitude, 25.4358);
      expect(result.point.longitude, 81.8463);
    });
  });
}
