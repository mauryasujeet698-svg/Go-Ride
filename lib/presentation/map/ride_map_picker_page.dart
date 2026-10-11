import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_ride/infrastructure/maps/open_map_providers.dart';

/// The map provider can be switched at build time without changing app code.
const String _tileUrl = String.fromEnvironment(
  'GO_RIDE_OSM_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

const LatLng _defaultCenter = LatLng(26.8467, 80.9462); // Lucknow, Uttar Pradesh.

enum RideMapTarget { pickup, destination }

class RideMapSelection {
  const RideMapSelection({this.pickup, this.destination, this.pickupLabel, this.destinationLabel});

  final LatLng? pickup;
  final LatLng? destination;
  final String? pickupLabel;
  final String? destinationLabel;
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
    this.routeFuture,
    super.key,
  });

  final LatLng? pickup;
  final LatLng? destination;
  final Future<RoadRoute?>? routeFuture;

  @override
  Widget build(BuildContext context) {
    final selectedPickup = pickup;
    final selectedDestination = destination;
    final hasPins = selectedPickup != null || selectedDestination != null;
    final center = selectedPickup != null && selectedDestination != null
        ? LatLng(
            (selectedPickup.latitude + selectedDestination.latitude) / 2.0,
            (selectedPickup.longitude + selectedDestination.longitude) / 2.0,
          )
        : selectedPickup ?? selectedDestination ?? _defaultCenter;
    final straightLineKm = selectedPickup != null && selectedDestination != null
        ? const Distance().as(LengthUnit.Kilometer, selectedPickup, selectedDestination)
        : 0.0;
    final previewZoom = straightLineKm > 100
        ? 6.5
        : straightLineKm > 30
            ? 8.0
            : straightLineKm > 10
                ? 9.5
                : straightLineKm > 3
                    ? 11.0
                    : hasPins ? 13.0 : 6.5;

    return FutureBuilder<RoadRoute?>(
      future: routeFuture,
      builder: (context, snapshot) {
        final route = snapshot.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 224,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: previewZoom,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl,
                      userAgentPackageName: 'com.goride.go_ride',
                    ),
                    if (route != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route.points,
                            color: const Color(0xFF00B84F),
                            strokeWidth: 4,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: _buildMarkers(
                        pickup: pickup,
                        destination: destination,
                      ),
                    ),
                    const RichAttributionWidget(
                      attributions: [
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.map_outlined, size: 16, color: Color(0xFF102235)),
                          const SizedBox(width: 6),
                          Text(
                            route != null
                                ? '${route.distanceLabel} · ${route.durationLabel}'
                                : routeFuture != null
                                    ? snapshot.connectionState == ConnectionState.waiting
                                        ? 'Calculating road route…'
                                        : 'Route unavailable'
                                    : hasPins ? 'Selected map pins' : 'Explore the map',
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
                if (routeFuture != null && snapshot.hasError)
                  const Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Text(
                      'Route service unavailable. Pin selection still works.',
                      style: TextStyle(color: Color(0xFF102235), fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
  final TextEditingController _searchController = TextEditingController();
  final OpenMapPlacesProvider _places = OpenMapPlacesProvider();

  late RideMapTarget _target;
  LatLng? _pickup;
  LatLng? _destination;
  bool _isLocating = false;
  bool _isSearching = false;
  bool _isResolvingAddress = false;
  List<PlaceSearchResult> _searchResults = [];
  String? _pickupLabel;
  String? _destinationLabel;

  LatLng get _activePoint {
    final active = _target == RideMapTarget.pickup ? _pickup : _destination;
    return active ?? _pickup ?? _destination ?? _defaultCenter;
  }

  double get _initialZoom {
    final active = _target == RideMapTarget.pickup ? _pickup : _destination;
    if (active != null) return 14;
    if (_pickup != null || _destination != null) return 11.5;
    return 6.5;
  }

  @override
  void initState() {
    super.initState();
    _target = widget.initialTarget;
    _pickup = widget.initialPickup;
    _destination = widget.initialDestination;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _places.close();
    super.dispose();
  }

  void _selectPoint(LatLng point) {
    setState(() {
      if (_target == RideMapTarget.pickup) {
        _pickup = point;
        _pickupLabel = null;
      } else {
        _destination = point;
        _destinationLabel = null;
      }
    });
  }

  Future<void> _searchPlaces() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_searchController.text.trim().length < 3) {
      _showMessage('Enter at least 3 characters to search for a place.');
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await _places.search(_searchController.text);
      if (!mounted) return;
      setState(() => _searchResults = results);
      if (results.isEmpty) _showMessage('No places found. Try a nearby landmark or address.');
    } catch (_) {
      if (mounted) _showMessage('Place search is unavailable. You can still choose a pin manually.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _choosePlace(PlaceSearchResult place) {
    setState(() {
      if (_target == RideMapTarget.pickup) {
        _pickup = place.point;
        _pickupLabel = place.label;
      } else {
        _destination = place.point;
        _destinationLabel = place.label;
      }
      _searchResults = [];
    });
    _mapController.move(place.point, 15);
  }

  Future<void> _resolveActiveAddress() async {
    final point = _target == RideMapTarget.pickup ? _pickup : _destination;
    if (point == null) {
      _showMessage('Choose a pin before looking up its address.');
      return;
    }
    setState(() => _isResolvingAddress = true);
    try {
      final label = await _places.reverseGeocode(point);
      if (!mounted) return;
      if (label == null) {
        _showMessage('No readable address was found for this pin.');
      } else {
        setState(() {
          if (_target == RideMapTarget.pickup) {
            _pickupLabel = label;
          } else {
            _destinationLabel = label;
          }
        });
      }
    } catch (_) {
      if (mounted) _showMessage('Address lookup is unavailable. The selected pin is still saved.');
    } finally {
      if (mounted) setState(() => _isResolvingAddress = false);
    }
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _searchPlaces(),
                        decoration: const InputDecoration(
                          labelText: 'Search address or landmark',
                          prefixIcon: Icon(Icons.search_rounded),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isSearching ? null : _searchPlaces,
                      tooltip: 'Search places',
                      icon: _isSearching
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search_rounded),
                    ),
                  ],
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 140),
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4EAF0)),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(result.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _choosePlace(result),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _activePoint,
                initialZoom: _initialZoom,
                onTap: (_, point) => _selectPoint(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  userAgentPackageName: 'com.goride.go_ride',
                ),
                MarkerLayer(
                  markers: _buildMarkers(
                    pickup: _pickup,
                    destination: _destination,
                  ),
                ),
                const RichAttributionWidget(
                  attributions: [
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
                    (_target == RideMapTarget.pickup ? _pickupLabel : _destinationLabel) ??
                        _coordinateSummary(_target == RideMapTarget.pickup ? _pickup : _destination),
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _isResolvingAddress ? null : _resolveActiveAddress,
                      icon: _isResolvingAddress
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.pin_drop_outlined, size: 18),
                      label: const Text('Find address for pin'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  FilledButton.icon(
                    onPressed: _pickup == null && _destination == null
                        ? null
                        : () => Navigator.of(context).pop(
                              RideMapSelection(
                                pickup: _pickup,
                                destination: _destination,
                                pickupLabel: _pickupLabel,
                                destinationLabel: _destinationLabel,
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
