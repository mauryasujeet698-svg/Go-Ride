import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// The map provider can be switched at build time without changing app code.
const String _tileUrl = String.fromEnvironment(
  'GO_RIDE_OSM_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const LatLng _defaultCenter = LatLng(26.8467, 80.9462); // Lucknow, Uttar Pradesh.

enum RideMapTarget { pickup, destination }

class RideMapSelection {
  const RideMapSelection({this.pickup, this.destination});

  final LatLng? pickup;
  final LatLng? destination;
}

/// Interactive map preview shown on the customer home screen.
///
/// Public OpenStreetMap tiles are best-effort and must not be treated as
/// unlimited production infrastructure. Configure a compliant provider through
/// GO_RIDE_OSM_TILE_URL before serving material traffic.
class RideMapPreview extends StatelessWidget {
  const RideMapPreview({
    this.pickup,
    this.destination,
    super.key,
  });

  final LatLng? pickup;
  final LatLng? destination;

  @override
  Widget build(BuildContext context) {
    final center = pickup ?? destination ?? _defaultCenter;
    final hasPins = pickup != null || destination != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 224,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: hasPins ? 13 : 6.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  userAgentPackageName: 'com.goride.app',
                ),
                MarkerLayer(
                  markers: _buildMarkers(
                    pickup: pickup,
                    destination: destination,
                  ),
                ),
                RichAttributionWidget(
                  attributions: const [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x18000000),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.map_outlined,
                        size: 16,
                        color: Color(0xFF102235),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasPins ? 'Selected map pins' : 'Explore the map',
                        style: const TextStyle(
                          color: Color(0xFF102235),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RideMapPickerPage extends StatefulWidget {
  const RideMapPickerPage({
    this.initialPickup,
    this.initialDestination,
    this.initialTarget = RideMapTarget.pickup,
    super.key,
  });

  final LatLng? initialPickup;
  final LatLng? initialDestination;
  final RideMapTarget initialTarget;

  @override
  State<RideMapPickerPage> createState() => _RideMapPickerPageState();
}

class _RideMapPickerPageState extends State<RideMapPickerPage> {
  final MapController _mapController = MapController();

  late RideMapTarget _target;
  LatLng? _pickup;
  LatLng? _destination;
  bool _isLocating = false;

  LatLng get _activePoint =>
      _target == RideMapTarget.pickup ? (_pickup ?? _defaultCenter) : (_destination ?? _defaultCenter);

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _pickup = widget.initialPickup;
    _destination = widget.initialDestination;
  }

  void _selectPoint(LatLng point) {
    setState(() {
      if (_target == RideMapTarget.pickup) {
        _pickup = point;
      } else {
        _destination = point;
      }
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Turn on location services, or move the map to choose a pin.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage(
          permission == LocationPermission.deniedForever
              ? 'Location permission is disabled in app settings. You can still choose a pin manually.'
              : 'Location permission was not granted. You can still choose a pin manually.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      final point = LatLng(position.latitude, position.longitude);
      _selectPoint(point);
      _mapController.move(point, 16);
    } catch (_) {
      _showMessage('Could not get your location. Move the map and tap to choose a pin.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text(
          'Choose locations',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _isLocating ? null : _useCurrentLocation,
            tooltip: 'Use current location for selected field',
            icon: _isLocating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SegmentedButton<RideMapTarget>(
              segments: const [
                ButtonSegment<RideMapTarget>(
                  value: RideMapTarget.pickup,
                  label: Text('Pickup'),
                  icon: Icon(Icons.radio_button_checked),
                ),
                ButtonSegment<RideMapTarget>(
                  value: RideMapTarget.destination,
                  label: Text('Destination'),
                  icon: Icon(Icons.location_on_outlined),
                ),
              ],
              selected: {_target},
              onSelectionChanged: (selection) {
                setState(() => _target = selection.first);
              },
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _activePoint,
                initialZoom: 13,
                onTap: (_, point) => _selectPoint(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  userAgentPackageName: 'com.goride.app',
                ),
                MarkerLayer(
                  markers: _buildMarkers(
                    pickup: _pickup,
                    destination: _destination,
                  ),
                ),
                RichAttributionWidget(
                  attributions: const [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Color(0xFFE4EAF0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _target == RideMapTarget.pickup
                        ? 'Tap the map to place the pickup pin'
                        : 'Tap the map to place the destination pin',
                    style: const TextStyle(
                      color: Color(0xFF102235),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _coordinateSummary(_target == RideMapTarget.pickup ? _pickup : _destination),
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _pickup == null && _destination == null
                        ? null
                        : () => Navigator.of(context).pop(
                              RideMapSelection(
                                pickup: _pickup,
                                destination: _destination,
                              ),
                            ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use selected pins'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: const Color(0xFF00B84F),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _coordinateSummary(LatLng? point) {
  if (point == null) return 'No pin selected yet';
  return '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
}

List<Marker> _buildMarkers({
  required LatLng? pickup,
  required LatLng? destination,
}) {
  return [
    if (pickup != null)
      Marker(
        point: pickup,
        width: 42,
        height: 42,
        alignment: Alignment.bottomCenter,
        child: const Icon(
          Icons.location_on_rounded,
          size: 42,
          color: Color(0xFF00B84F),
          shadows: [Shadow(color: Colors.white, blurRadius: 3)],
        ),
      ),
    if (destination != null)
      Marker(
        point: destination,
        width: 42,
        height: 42,
        alignment: Alignment.bottomCenter,
        child: const Icon(
          Icons.location_on_rounded,
          size: 42,
          color: Color(0xFF102235),
          shadows: [Shadow(color: Colors.white, blurRadius: 3)],
        ),
      ),
  ];
}
