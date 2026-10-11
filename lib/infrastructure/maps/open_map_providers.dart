import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Provider-neutral location search and road-routing adapter.
///
/// The public Nominatim and OSRM demo endpoints are development conveniences,
/// not an SLA-backed production service. Replace these endpoints or provide
/// compliant hosted/self-hosted services before a public launch.
class OpenMapPlacesProvider {
  OpenMapPlacesProvider({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<List<PlaceSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '6',
      'countrycodes': 'in',
    });
    final response = await _client.get(uri, headers: const {
      'Accept': 'application/json',
      'User-Agent': 'GoRide/1.0 (Flutter customer app)',
    }).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('Place search is unavailable (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw const FormatException('Invalid place search response.');

    return decoded.whereType<Map<String, dynamic>>().map((item) {
      final lat = double.tryParse('${item['lat'] ?? ''}');
      final lon = double.tryParse('${item['lon'] ?? ''}');
      final name = (item['display_name'] as String? ?? '').trim();
      if (lat == null || lon == null || name.isEmpty) return null;
      return PlaceSearchResult(
        label: name,
        point: LatLng(lat, lon),
      );
    }).whereType<PlaceSearchResult>().toList(growable: false);
  }

  Future<String?> reverseGeocode(LatLng point) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'format': 'jsonv2',
    });
    final response = await _client.get(uri, headers: const {
      'Accept': 'application/json',
      'User-Agent': 'GoRide/1.0 (Flutter customer app)',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Address lookup is unavailable (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid reverse-geocoding response.');
    }
    final label = decoded['display_name'];
    return label is String && label.trim().isNotEmpty ? label.trim() : null;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class PlaceSearchResult {
  const PlaceSearchResult({required this.label, required this.point});

  final String label;
  final LatLng point;
}

/// Returns a real road route from the OSRM demo service, when available.
class OpenMapRoutingProvider {
  OpenMapRoutingProvider({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  String? _cachedKey;
  Future<RoadRoute?>? _cachedFuture;

  Future<RoadRoute?> route(LatLng pickup, LatLng destination) {
    final key = '${pickup.latitude},${pickup.longitude}:${destination.latitude},${destination.longitude}';
    if (_cachedKey == key && _cachedFuture != null) return _cachedFuture!;
    _cachedKey = key;
    return _cachedFuture = _fetchRoute(pickup, destination);
  }

  Future<RoadRoute?> _fetchRoute(LatLng pickup, LatLng destination) async {
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/${pickup.longitude},${pickup.latitude};${destination.longitude},${destination.latitude}',
      {'overview': 'full', 'geometries': 'geojson', 'steps': 'false'},
    );
    try {
      final response = await _client.get(uri, headers: const {
        'Accept': 'application/json',
        'User-Agent': 'GoRide/1.0 (Flutter customer app)',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['code'] != 'Ok') return null;
      final routes = decoded['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map<String, dynamic>) return null;
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'];
      final coordinates = geometry is Map<String, dynamic> ? geometry['coordinates'] : null;
      if (coordinates is! List) return null;
      final points = <LatLng>[];
      for (final item in coordinates) {
        if (item is List && item.length >= 2 && item[0] is num && item[1] is num) {
          points.add(LatLng((item[1] as num).toDouble(), (item[0] as num).toDouble()));
        }
      }
      final distance = route['distance'];
      final duration = route['duration'];
      if (points.length < 2 || distance is! num || duration is! num) return null;
      return RoadRoute(
        points: points,
        distanceMeters: distance.toDouble(),
        durationSeconds: duration.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class RoadRoute {
  const RoadRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  String get distanceLabel => distanceMeters >= 1000
      ? '${((distanceMeters / 100).round() / 10).toStringAsFixed(1)} km'
      : '${distanceMeters.round()} m';

  String get durationLabel {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '≈ $minutes min';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return '≈ ${hours}h ${remainder}m';
  }
}
