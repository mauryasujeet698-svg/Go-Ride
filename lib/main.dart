import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_config.dart';
import 'data/ride_backend.dart';

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { final prefs = await SharedPreferences.getInstance(); appThemeMode.value = switch (prefs.getString('go_ride_theme') ?? 'light') { 'light' => ThemeMode.light, 'system' => ThemeMode.system, _ => ThemeMode.dark }; } catch (_) {}
  var backendReady = false;
  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    ).timeout(const Duration(seconds: 8));
    backendReady = true;
  } catch (error, stackTrace) {
    // Keep the app inspectable even if backend setup or storage initialization fails.
    debugPrint('Go-Ride backend unavailable at launch: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  runApp(GoRideApp(backendReady: backendReady));
}

class GoRideApp extends StatelessWidget {
  const GoRideApp({super.key, required this.backendReady});
  final bool backendReady;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(valueListenable: appThemeMode, builder: (context, selectedTheme, _) => MaterialApp(
    title: 'Go-Ride',
    themeMode: selectedTheme,
    theme: ThemeData.light(useMaterial3: true),
    debugShowCheckedModeBanner: false,
    darkTheme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFFFFFFF),
        brightness: Brightness.dark,
      ).copyWith(
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: const Color(0xFFB9D5CE),
        surface: const Color(0xFF202020),
      ),
      scaffoldBackgroundColor: const Color(0xFF101010),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF101010),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF252525),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Color(0xFF454545)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Colors.white, width: 1.5),
        ),
        labelStyle: TextStyle(color: Color(0xFFBBBBBB)),
        hintStyle: TextStyle(color: Color(0xFF888888)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF555555)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        ),
      ),
    ),
    home: AuthGate(backendReady: backendReady),
  ));
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.backendReady});
  final bool backendReady;

  @override
  Widget build(BuildContext context) {
    if (!backendReady) return const PreviewHomeScreen(backendReady: false);
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) => Supabase.instance.client.auth.currentSession == null
        ? const PreviewHomeScreen(backendReady: true) : const RideHomeScreen(),
    );
  }
}


class PendingBooking {
  static GeoPoint? pickup;
  static GeoPoint? destination;
  static String pickupLabel = '';
  static String destinationLabel = '';
  static String category = '';
}

class PlaceResult {
  const PlaceResult({required this.label, required this.point});
  final String label;
  final GeoPoint point;
}

class GuestFare {
  const GuestFare({required this.category, required this.amountMinor, required this.currency, required this.etaSeconds});
  final String category;
  final int amountMinor;
  final String currency;
  final int etaSeconds;
}

class PreviewHomeScreen extends StatefulWidget {
  const PreviewHomeScreen({super.key, required this.backendReady});
  final bool backendReady;
  @override
  State<PreviewHomeScreen> createState() => _PreviewHomeScreenState();
}

class _PreviewHomeScreenState extends State<PreviewHomeScreen> {
  static const _mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  static const _osmTileUrl = String.fromEnvironment('OSM_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  static const _mapboxTileUrl = 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}?access_token={accessToken}';
  static String get _tileUrl => _mapboxToken.isEmpty ? _osmTileUrl : _mapboxTileUrl;
  static const _nominatim = String.fromEnvironment('GEOCODER_URL', defaultValue: 'https://nominatim.openstreetmap.org');
  static const _osrm = String.fromEnvironment('ROUTING_URL', defaultValue: 'https://router.project-osrm.org');
  final pickup = TextEditingController();
  final destination = TextEditingController();
  final mapController = MapController();
  GeoPoint? pickupPoint, destinationPoint;
  List<ll.LatLng> route = [];
  List<GuestFare> fares = [];
  bool busy = false, locating = false, choosePickup = false;
  bool planningRoute = false;
  String? preferredCategory;
  String? error, info;
  double? distanceKm;
  int? routeSeconds;

  @override
  void dispose() { pickup.dispose(); destination.dispose(); mapController.dispose(); super.dispose(); }

  Future<void> locatePickup() async {
    setState(() { locating = true; error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Enable location services or search for your pickup address.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('Location permission was not granted. You can still search for a pickup address.');
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
      pickupPoint = GeoPoint(p.latitude, p.longitude);
      pickup.text = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
      try {
        final r = await http.get(Uri.parse('$_nominatim/reverse?format=jsonv2&lat=${p.latitude}&lon=${p.longitude}'), headers: {'User-Agent':'GoRideCustomer/0.1'}).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) pickup.text = (jsonDecode(r.body) as Map<String,dynamic>)['display_name']?.toString() ?? pickup.text;
      } catch (_) {}
      _moveMap(pickupPoint!);
      if (mounted) setState(() => info = 'Pickup location set.');
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ','')); }
    finally { if (mounted) setState(() => locating = false); }
  }

  Future<void> searchAddress({required bool forPickup}) async {
    final query = (forPickup ? pickup.text : destination.text).trim();
    if (query.isEmpty) { setState(() => error = 'Enter an address to search.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final uri = Uri.parse('$_nominatim/search').replace(queryParameters: {'q': query, 'format':'jsonv2', 'limit':'5', 'addressdetails':'1', 'countrycodes':'in'});
      final response = await http.get(uri, headers: {'User-Agent':'GoRideCustomer/0.1'}).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw Exception('Address search is temporarily unavailable. Try again shortly.');
      final rows = (jsonDecode(response.body) as List).cast<Map<String,dynamic>>();
      if (rows.isEmpty) throw Exception('No matching address found. Try adding the city or area.');
      final options = rows.map((m) => PlaceResult(label: m['display_name'].toString(), point: GeoPoint(double.parse(m['lat'].toString()), double.parse(m['lon'].toString())))).toList();
      if (!mounted) return;
      if (options.length == 1) { _selectPlace(options.first, forPickup: forPickup); }
      else {
        await showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(child: ListView(shrinkWrap:true, children: [
          const ListTile(title: Text('Choose an address')),
          for (final option in options) ListTile(leading: const Icon(Icons.place_outlined), title: Text(option.label, maxLines: 3, overflow: TextOverflow.ellipsis), onTap: () { Navigator.pop(ctx); _selectPlace(option, forPickup: forPickup); }),
        ])));
      }
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ','')); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void _selectPlace(PlaceResult result, {required bool forPickup}) {
    setState(() {
      if (forPickup) { pickupPoint = result.point; pickup.text = result.label; }
      else { destinationPoint = result.point; destination.text = result.label; }
      fares = []; route = []; distanceKm = null; routeSeconds = null; info = null; error = null;
    });
    _moveMap(forPickup ? pickupPoint! : destinationPoint!);
    if (pickupPoint != null && destinationPoint != null) getRouteAndFares();
  }

  void _moveMap(GeoPoint point) { try { mapController.move(ll.LatLng(point.latitude, point.longitude), 14); } catch (_) {} }

  void _mapTap(TapPosition tap, ll.LatLng point) {
    final selected = GeoPoint(point.latitude, point.longitude);
    setState(() {
      if (choosePickup || pickupPoint == null) { pickupPoint = selected; pickup.text = '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}'; }
      else { destinationPoint = selected; destination.text = '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}'; }
      choosePickup = false; fares = []; route = []; distanceKm = null; routeSeconds = null;
      info = 'Map location selected. Search an address if you want a readable place name.';
    });
    if (pickupPoint != null && destinationPoint != null) getRouteAndFares();
  }

  Future<PlaceResult> _resolveTypedPlace(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) throw Exception('Enter both a pickup and destination.');
    final withCountry = RegExp(r'\bIndia\b', caseSensitive: false).hasMatch(query)
        ? query : '$query, India';
    final uri = Uri.parse('$_nominatim/search').replace(queryParameters: {
      'q': withCountry,
      'format': 'jsonv2',
      'limit': '5',
      'addressdetails': '1',
      'countrycodes': 'in',
    });
    final response = await http.get(
      uri,
      headers: {'User-Agent': 'GoRideCustomer/1.0 (support: app)'},
    ).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw Exception('Address search is temporarily unavailable. Try again shortly.');
    }
    final rows = (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) throw Exception('No matching place found for "$query". Add the nearby town or district.');
    final place = rows.first;
    return PlaceResult(
      label: place['display_name']?.toString() ?? query,
      point: GeoPoint(
        double.parse(place['lat'].toString()),
        double.parse(place['lon'].toString()),
      ),
    );
  }

  Future<void> getRouteAndFares() async {
    FocusScope.of(context).unfocus();
    if (pickup.text.trim().isEmpty || destination.text.trim().isEmpty) {
      setState(() => error = 'Enter both pickup and destination first.');
      return;
    }
    setState(() { busy = true; error = null; info = null; fares = []; });
    try {
      // Text entered by the customer is a valid input; it must not require the
      // customer to separately tap the small search icon before requesting a route.
      var a = pickupPoint;
      var b = destinationPoint;
      if (a == null) {
        final selected = await _resolveTypedPlace(pickup.text);
        a = selected.point;
        pickupPoint = selected.point;
        pickup.text = selected.label;
      }
      if (b == null) {
        final selected = await _resolveTypedPlace(destination.text);
        b = selected.point;
        destinationPoint = selected.point;
        destination.text = selected.label;
      }
      final uri = Uri.parse('$_osrm/route/v1/driving/${a.longitude},${a.latitude};${b.longitude},${b.latitude}').replace(queryParameters: {'overview':'full','geometries':'geojson','steps':'false'});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Route service is unavailable. Try again later.');
      final data = jsonDecode(response.body) as Map<String,dynamic>;
      if (data['code'] != null && data['code'] != 'Ok') {
        throw Exception('No drivable route was found between these places.');
      }
      final routes = (data['routes'] as List?) ?? [];
      if (routes.isEmpty) throw Exception('No drivable route was found between those locations.');
      final r = Map<String,dynamic>.from(routes.first as Map);
      final coords = (r['geometry']['coordinates'] as List).cast<List<dynamic>>();
      final points = coords.map((c) => ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      final km = (r['distance'] as num).toDouble()/1000;
      final secs = (r['duration'] as num).round();
      if (km > 200) throw Exception('This service currently supports trips up to 200 km.');
      List<GuestFare> quotes = [];
      if (widget.backendReady) {
        // Guest fare RPC execution is intentionally revoked for client roles.
        // Call the hardened Edge Function, which invokes the RPC server-side.
        final fareResponse = await Supabase.instance.client.functions.invoke(
          'estimate-route-fares',
          body: {
            'pickup': {'latitude': a.latitude, 'longitude': a.longitude},
            'destination': {'latitude': b.latitude, 'longitude': b.longitude},
          },
        );
        final payload = Map<String, dynamic>.from(fareResponse.data as Map);
        final rawFares = payload['fares'];
        if (fareResponse.status < 200 || fareResponse.status >= 300 || rawFares is! List) {
          final code = payload['error']?.toString() ?? 'fare_estimate_unavailable';
          throw Exception(switch (code) {
            'trip_too_long' => 'This service currently supports trips up to 200 km.',
            'routing_unavailable' => 'Fare routing is temporarily unavailable. Try again shortly.',
            'server_configuration_missing' => 'Fare service setup is incomplete. Please try again later.',
            _ => 'Fare estimates are temporarily unavailable. Please try again shortly.',
          });
        }
        quotes = rawFares.map((x) {
          final m = Map<String, dynamic>.from(x as Map);
          return GuestFare(
            category: m['category'].toString(),
            amountMinor: (m['amount_minor'] as num).toInt(),
            currency: m['currency'].toString().trim(),
            etaSeconds: (m['eta_seconds'] as num).toInt(),
          );
        }).toList();
      }
      if (!mounted) return;
      setState(() {
        route = points;
        distanceKm = km;
        routeSeconds = secs;
        fares = quotes;
        info = quotes.isEmpty
          ? 'Route found. Fare estimates are temporarily unavailable; no prices have been invented.'
          : 'Choose a ride to continue. Fare and driver availability are rechecked before booking.';
      });
      if (points.isNotEmpty) {
        mapController.fitCamera(
          CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(44)),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> book(GuestFare fare) async {
    if (pickupPoint == null || destinationPoint == null) { setState(() => error = 'Set both pickup and destination before continuing.'); return; }
    PendingBooking.pickup = pickupPoint; PendingBooking.destination = destinationPoint;
    PendingBooking.pickupLabel = pickup.text.trim(); PendingBooking.destinationLabel = destination.text.trim(); PendingBooking.category = fare.category;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => BookingReviewScreen(
      pickupLabel: pickup.text.trim(), destinationLabel: destination.text.trim(), category: fare.category,
      amountMinor: fare.amountMinor, currency: fare.currency, distanceKm: distanceKm ?? 0,
      etaSeconds: fare.etaSeconds, backendReady: widget.backendReady)));
  }


  @override
  Widget build(BuildContext context) {
    final center = pickupPoint != null
        ? ll.LatLng(pickupPoint!.latitude, pickupPoint!.longitude)
        : const ll.LatLng(25.89, 81.99);
    final visibleFares = preferredCategory == null
        ? fares
        : fares.where((fare) => fare.category.toUpperCase() == preferredCategory).toList();

    void openSection(String section) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => section == 'account' ? AccountScreen(backendReady: widget.backendReady) : section == 'settings' ? SettingsScreen(backendReady: widget.backendReady) : section == 'history' ? HistoryScreen(backendReady: widget.backendReady) : CustomerSectionScreen(section: section, backendReady: widget.backendReady),
        ),
      );
    }

    void chooseCategory(String category) {
      setState(() {
        preferredCategory = category;
        planningRoute = true;
        error = null;
        info = null;
      });
    }

    Widget serviceTile({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    color: Color(0xFF292929),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Go-Ride'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account and trips',
            onSelected: (section) {
              if (section == 'signin') {
                if (!widget.backendReady) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Sign-in is temporarily unavailable because backend configuration is missing.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => LoginScreen(
                      onSignedIn: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              } else {
                openSection(section);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: Icon(Icons.history),
                  title: Text('Ride history'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'saved',
                child: ListTile(
                  leading: Icon(Icons.bookmark_outline),
                  title: Text('Saved places'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'support',
                child: ListTile(
                  leading: Icon(Icons.support_agent),
                  title: Text('Customer support'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('My profile'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'signin',
                child: ListTile(
                  leading: Icon(Icons.login),
                  title: Text('Sign in to book'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            const Text(
              'Where would you like to go?',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Compare local ride options without signing in. Sign in only when you are ready to request a real ride.',
              style: TextStyle(color: Color(0xFFBBBBBB), height: 1.35),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const Key('destination-search'),
              controller: destination,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: planningRoute ? 'Destination' : null,
                hintText: 'Where to?',
                prefixIcon: const Icon(Icons.search, size: 25),
                suffixIcon: IconButton(
                  tooltip: planningRoute ? 'Search destination' : 'Plan a ride',
                  onPressed: busy
                      ? null
                      : () {
                          if (!planningRoute) {
                            setState(() => planningRoute = true);
                          } else {
                            searchAddress(forPickup: false);
                          }
                        },
                  icon: Icon(
                    planningRoute ? Icons.arrow_forward : Icons.north_east,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 19,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(32),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.4),
                ),
              ),
              onTap: () {
                if (!planningRoute) {
                  setState(() => planningRoute = true);
                }
              },
              onChanged: (_) => setState(() {
                destinationPoint = null;
                route = [];
                fares = [];
                distanceKm = null;
                error = null;
                info = null;
              }),
              onSubmitted: (_) {
                setState(() => planningRoute = true);
                getRouteAndFares();
              },
            ),
            if (!planningRoute) ...[
              const SizedBox(height: 16),
              Material(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () async {
                    setState(() {
                      planningRoute = true;
                      error = null;
                    });
                    if (pickupPoint == null) {
                      await locatePickup();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Container(
                          height: 52,
                          width: 52,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.history, size: 25),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickup.text.trim().isEmpty
                                    ? 'Set your pickup'
                                    : pickup.text.trim(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'Pickup location',
                                style: TextStyle(color: Color(0xFFB8B8B8)),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2E5DF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your town. Your ride.',
                            style: TextStyle(
                              color: Color(0xFF161616),
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'See your route and compare upfront fare estimates.',
                            style: TextStyle(
                              color: Color(0xFF3A3A3A),
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E1E1E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                            ),
                            onPressed: () => setState(() {
                              planningRoute = true;
                              preferredCategory = null;
                            }),
                            child: const Text('Plan a ride'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 116,
                      width: 90,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3D0C6),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.route_rounded,
                        color: Color(0xFF1E1E1E),
                        size: 66,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'For you',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Compare all ride types',
                    onPressed: () => setState(() {
                      planningRoute = true;
                      preferredCategory = null;
                    }),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.89,
                children: [
                  serviceTile(
                    icon: Icons.two_wheeler,
                    label: 'Bike',
                    onTap: () => chooseCategory('BIKE'),
                  ),
                  serviceTile(
                    icon: Icons.electric_rickshaw,
                    label: 'Auto',
                    onTap: () => chooseCategory('AUTO'),
                  ),
                  serviceTile(
                    icon: Icons.directions_car_filled,
                    label: 'Mini',
                    onTap: () => chooseCategory('MINI'),
                  ),
                  serviceTile(
                    icon: Icons.local_taxi,
                    label: 'Sedan',
                    onTap: () => chooseCategory('SEDAN'),
                  ),
                  serviceTile(
                    icon: Icons.bookmark_outline,
                    label: 'Saved places',
                    onTap: () => openSection('saved'),
                  ),
                  serviceTile(
                    icon: Icons.receipt_long_outlined,
                    label: 'Activity',
                    onTap: () => openSection('history'),
                  ),
                  serviceTile(
                    icon: Icons.support_agent,
                    label: 'Support',
                    onTap: () => openSection('support'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back to home',
                    onPressed: () => setState(() {
                      planningRoute = false;
                      choosePickup = false;
                    }),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Text(
                      'Plan your ride',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (preferredCategory != null)
                    TextButton(
                      onPressed: () => setState(() => preferredCategory = null),
                      child: const Text('All rides'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('pickup-search'),
                controller: pickup,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Pickup location',
                  hintText: 'Enter a pickup or use your location',
                  prefixIcon: const Icon(Icons.trip_origin),
                  suffixIcon: IconButton(
                    tooltip: 'Search pickup',
                    onPressed: busy ? null : () => searchAddress(forPickup: true),
                    icon: const Icon(Icons.search),
                  ),
                ),
                onChanged: (_) => setState(() {
                  pickupPoint = null;
                  route = [];
                  fares = [];
                  distanceKm = null;
                  error = null;
                  info = null;
                }),
                onSubmitted: (_) => searchAddress(forPickup: true),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: locating ? null : locatePickup,
                      icon: locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: const Text('Use my location'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() {
                        choosePickup = true;
                        info = 'Tap the map to choose your pickup.';
                      }),
                      icon: const Icon(Icons.touch_app),
                      label: const Text('Set pickup on map'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  height: 260,
                  child: FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 11,
                      onTap: _mapTap,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: _tileUrl,
                        additionalOptions: const {'accessToken': _mapboxToken},
                        userAgentPackageName: 'com.goride.customer',
                        maxZoom: 19,
                      ),
                      if (route.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: route,
                              color: Theme.of(context).colorScheme.primary,
                              strokeWidth: 5,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          if (pickupPoint != null)
                            Marker(
                              point: ll.LatLng(
                                pickupPoint!.latitude,
                                pickupPoint!.longitude,
                              ),
                              width: 42,
                              height: 42,
                              child: const Icon(
                                Icons.trip_origin,
                                color: Color(0xFFB9D5CE),
                                size: 32,
                              ),
                            ),
                          if (destinationPoint != null)
                            Marker(
                              point: ll.LatLng(
                                destinationPoint!.latitude,
                                destinationPoint!.longitude,
                              ),
                              width: 42,
                              height: 42,
                              child: Icon(
                                Icons.location_pin,
                                color: Theme.of(context).colorScheme.primary,
                                size: 40,
                              ),
                            ),
                        ],
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('© OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy ? null : getRouteAndFares,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.route),
                label: Text(
                  busy ? 'Finding route…' : 'Show route and fares',
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Message(text: error!, isError: true),
            ],
            if (info != null) ...[
              const SizedBox(height: 10),
              Message(text: info!),
            ],
            if (distanceKm != null && planningRoute)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.route),
                  title: Text('${distanceKm!.toStringAsFixed(1)} km by road'),
                  subtitle: Text(
                    'Estimated travel time ${((routeSeconds ?? 0) / 60).ceil()} min',
                  ),
                ),
              ),
            if (visibleFares.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Choose a ride',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (preferredCategory != null)
                    TextButton(
                      onPressed: () => setState(() => preferredCategory = null),
                      child: const Text('Compare all'),
                    ),
                ],
              ),
              for (final fare in visibleFares)
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: ListTile(
                    leading: Icon(
                      fare.category == 'BIKE'
                          ? Icons.two_wheeler
                          : fare.category == 'AUTO'
                          ? Icons.electric_rickshaw
                          : fare.category == 'MINI'
                              ? Icons.directions_car_filled
                              : Icons.local_taxi,
                      size: 30,
                    ),
                    title: Text(fare.category),
                    subtitle: Text(
                      'Estimated arrival ${(fare.etaSeconds / 60).ceil()} min · route ${distanceKm!.toStringAsFixed(1)} km',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${fare.currency} ${(fare.amountMinor / 100).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Text('Book', style: TextStyle(color: Color(0xFFB9D5CE))),
                      ],
                    ),
                    onTap: () => book(fare),
                  ),
                ),
            ],
            if (preferredCategory != null &&
                fares.isNotEmpty &&
                visibleFares.isEmpty)
              Message(
                text: 'This ride type is not available for the selected route. Compare all rides instead.',
                isError: true,
              ),
            if (planningRoute)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Text(
                  'Map data © OpenStreetMap contributors. Routing and address-search endpoints are public development defaults; configure a production provider before launch.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: Theme.of(context).colorScheme.secondaryContainer,
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 0) {
            setState(() => planningRoute = false);
            return;
          }
          if (index == 1) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ServicesScreen()),
            );
            return;
          }
          if (index == 2) {
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ParcelScreen()),
            );
            return;
          }
          if (index == 3) openSection('account');
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Services',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Parcel',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.onSignedIn});
  final VoidCallback? onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  StreamSubscription<AuthState>? authSubscription;
  final phone = TextEditingController();
  final otp = TextEditingController();
  bool sent = false, busy = false;
  String? error;
  String get phoneE164 {
    final raw = phone.text.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (raw.startsWith('+')) return raw;
    if (raw.length == 10) return '+91$raw';
    return raw;
  }
  @override
  void initState() {
    super.initState();
    authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.session != null && mounted) widget.onSignedIn?.call();
    });
  }
  @override
  void dispose() { authSubscription?.cancel(); phone.dispose(); otp.dispose(); super.dispose(); }
  Future<void> requestOtp() async {
    if (!phoneE164.startsWith('+') || phoneE164.length < 10) { setState(() => error = 'Enter a valid phone number.'); return; }
    setState(() { busy = true; error = null; });
    try {
      await Supabase.instance.client.auth.signInWithOtp(phone: phoneE164);
      if (mounted) setState(() => sent = true);
    } on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'Could not send the code. Check your connection.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> verifyOtp() async {
    if (otp.text.trim().length < 4) { setState(() => error = 'Enter the SMS verification code.'); return; }
    setState(() { busy = true; error = null; });
    try {
      await Supabase.instance.client.auth.verifyOTP(phone: phoneE164, token: otp.text.trim(), type: OtpType.sms);
    } on AuthException catch (e) { if (mounted) setState(() => error = e.message); }
    catch (_) { if (mounted) setState(() => error = 'Verification failed. Please try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.local_taxi_rounded, size: 64, color: Color(0xFF087E72)),
          const SizedBox(height: 12),
          Text('Go-Ride', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Reliable rides, one tap away.', textAlign: TextAlign.center),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: busy ? null : () async {
              setState(() { busy = true; error = null; });
              try {
                await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: 'io.supabase.goride://login-callback/');
              } on AuthException catch (e) {
                if (mounted) setState(() => error = e.message);
              } catch (_) {
                if (mounted) setState(() => error = 'Google sign-in could not be started. Check OAuth configuration.');
              } finally { if (mounted) setState(() => busy = false); }
            },
            icon: const Icon(Icons.g_mobiledata, size: 28),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 16),
          const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR USE MOBILE NUMBER')), Expanded(child: Divider())]),
          const SizedBox(height: 16),
          TextField(controller: phone, keyboardType: TextInputType.phone, enabled: !sent && !busy,
            decoration: const InputDecoration(labelText: 'Mobile number', hintText: '98765 43210', prefixIcon: Icon(Icons.phone_android), helperText: 'Indian numbers can be entered without +91.')),
          if (sent) ...[
            const SizedBox(height: 12),
            TextField(controller: otp, keyboardType: TextInputType.number, autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(labelText: 'SMS verification code', prefixIcon: Icon(Icons.lock_outline))),
          ],
          if (error != null) ...[const SizedBox(height: 12), Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          const SizedBox(height: 20),
          FilledButton(onPressed: busy ? null : (sent ? verifyOtp : requestOtp),
            child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(sent ? 'Verify and continue' : 'Send verification code')),
          if (sent) TextButton(onPressed: busy ? null : () => setState(() { sent = false; otp.clear(); error = null; }), child: const Text('Change mobile number')),
          const SizedBox(height: 16),
          const Text('Never share your verification code with anyone.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      )),
    ))),
  );
}

class RideHomeScreen extends StatefulWidget {
  const RideHomeScreen({super.key});
  @override
  State<RideHomeScreen> createState() => _RideHomeScreenState();
}
class _RideHomeScreenState extends State<RideHomeScreen> {
  static const _mapboxToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
  static const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _mapboxTileUrl = 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}?access_token={accessToken}';
  static String get _tileUrl => _mapboxToken.isEmpty ? _osmTileUrl : _mapboxTileUrl;
  static const _routingUrl = 'https://router.project-osrm.org';
  final pickupText = TextEditingController();
  final destinationText = TextEditingController();
  final mapController = MapController();
  final backend = RideBackend(Supabase.instance.client);
  GeoPoint? pickup, destination;
  List<ll.LatLng> routePoints = [];
  bool choosePickupOnMap = false;
  List<FareQuote> quotes = [];
  RideRecord? ride;
  StreamSubscription<List<Map<String, dynamic>>>? eventSub;
  bool busy = false, locating = false;
  String? error, notice;
  int lastSeq = 0;

  @override
  void initState() {
    super.initState();
    restoreRide();
    final pendingPickup = PendingBooking.pickup;
    final pendingDestination = PendingBooking.destination;
    if (pendingPickup != null && pendingDestination != null) {
      pickup = pendingPickup;
      destination = pendingDestination;
      pickupText.text = PendingBooking.pickupLabel;
      destinationText.text = PendingBooking.destinationLabel;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) estimate(); });
    } else { locate(); }
  }
  @override
  void dispose() { eventSub?.cancel(); pickupText.dispose(); destinationText.dispose(); mapController.dispose(); super.dispose(); }

  void _mapTap(TapPosition tap, ll.LatLng point) {
    setState(() {
      final selected = GeoPoint(point.latitude, point.longitude);
      if (choosePickupOnMap || pickup == null) {
        pickup = selected;
        pickupText.text = '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
        choosePickupOnMap = false;
      } else {
        destination = selected;
        destinationText.text = '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
      }
      routePoints = [];
      quotes = [];
      error = null;
      notice = 'Location selected on map. Get fares to continue.';
    });
    _moveMap(point);
  }

  void _moveMap(ll.LatLng point) {
    try { mapController.move(point, 14); } catch (_) {}
  }

  Future<void> _loadRouteShape() async {
    final a = pickup;
    final b = destination;
    if (a == null || b == null) return;
    try {
      final uri = Uri.parse('$_routingUrl/route/v1/driving/${a.longitude},${a.latitude};${b.longitude},${b.latitude}')
          .replace(queryParameters: {'overview': 'full', 'geometries': 'geojson', 'steps': 'false'});
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = (data['routes'] as List?) ?? [];
      if (routes.isEmpty) return;
      final geometry = Map<String, dynamic>.from(routes.first as Map)['geometry'] as Map<String, dynamic>;
      final coords = (geometry['coordinates'] as List).cast<List<dynamic>>();
      final points = coords.map((c) => ll.LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())).toList();
      if (!mounted || points.isEmpty) return;
      setState(() => routePoints = points);
      mapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(48)));
    } catch (_) {
      // Route pricing and booking use the backend; the visible line is an enhancement.
    }
  }

  Future<void> restoreRide() async {
    try {
      final r = await backend.activeRide();
      if (!mounted || r == null) return;
      setState(() {
        ride = r;
        pickup = r.pickup;
        destination = r.destination;
        pickupText.text = '${r.pickup.latitude.toStringAsFixed(5)}, ${r.pickup.longitude.toStringAsFixed(5)}';
        destinationText.text = '${r.destination.latitude.toStringAsFixed(5)}, ${r.destination.longitude.toStringAsFixed(5)}';
      });
      watchRide(r);
      await _loadRouteShape();
    } catch (_) {
      if (mounted) setState(() => notice = 'Could not restore the previous ride.');
    }
  }

  Future<void> locate() async {
    setState(() { locating = true; error = null; });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Turn on location services to set your pickup.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('Location permission is needed for pickup.');
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
      pickup = GeoPoint(p.latitude, p.longitude);
      _moveMap(ll.LatLng(p.latitude, p.longitude));
      var label = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
      try {
        final list = await placemarkFromCoordinates(p.latitude, p.longitude);
        if (list.isNotEmpty) {
          final x = list.first;
          final parts = [x.name, x.subLocality, x.locality, x.administrativeArea].whereType<String>().where((s) => s.trim().isNotEmpty).toSet();
          if (parts.isNotEmpty) label = parts.join(', ');
        }
      } catch (_) {}
      if (mounted) setState(() => pickupText.text = label);
    } catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => locating = false); }
  }

  Future<void> estimate() async {
    FocusScope.of(context).unfocus();
    if (pickup == null) { await locate(); if (pickup == null) return; }
    if (destinationText.text.trim().isEmpty) { setState(() => error = 'Enter a destination address.'); return; }
    setState(() { busy = true; error = null; notice = null; quotes = []; });
    try {
      if (destination == null) {
        final places = await locationFromAddress(destinationText.text.trim());
        if (places.isEmpty) throw Exception('Could not find that address. Try a fuller destination.');
        destination = GeoPoint(places.first.latitude, places.first.longitude);
      }
      final result = await backend.estimate(pickup!, destination!);
      await _loadRouteShape();
      if (mounted) setState(() { quotes = result; if (result.isEmpty) notice = 'No ride categories are currently available.'; });
    } on PostgrestException catch (e) { if (mounted) setState(() => error = friendlyError(e.message)); }
    catch (e) { if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => busy = false); }
  }

  String friendlyError(String raw) {
    if (raw.contains('authentication_required') || raw.contains('JWT')) return 'Your session expired. Sign in again.';
    if (raw.contains('rate_limited')) return 'Too many fare requests. Wait a minute and retry.';
    if (raw.contains('trip_too_long')) return 'This destination is too far for this service.';
    if (raw.contains('active_ride_exists')) return 'You already have an active ride.';
    return 'Request failed. Check your connection and try again.';
  }

  Future<void> book(FareQuote q) async {
    if (pickup == null || destination == null || busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm your ride'),
        content: Text('Book ${q.category} for an estimated ${q.currency} ${(q.amountMinor / 100).toStringAsFixed(0)}? The fare and availability will be checked again before the ride is created.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Confirm booking')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() { busy = true; error = null; });
    try {
      final r = await backend.createRide(quote: q, pickupLabel: pickupText.text.trim(), destinationLabel: destinationText.text.trim());
      if (!mounted) return;
      setState(() { ride = r; quotes = []; lastSeq = r.sequence; notice = 'Ride requested. We are looking for a driver.'; });
      watchRide(r);
    } on PostgrestException catch (e) { if (mounted) setState(() => error = friendlyError(e.message)); }
    catch (_) { if (mounted) setState(() => error = 'Booking failed. Please try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void watchRide(RideRecord r) {
    eventSub?.cancel();
    lastSeq = r.sequence;
    eventSub = backend.rideEvents(r.id).listen((rows) {
      if (rows.isEmpty) return;
      final maxSeq = rows.map((x) => (x['seq'] as num?)?.toInt() ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
      if (maxSeq > lastSeq) { lastSeq = maxSeq; refreshRide(r.id); }
    }, onError: (_) { if (mounted) setState(() => notice = 'Live updates disconnected. Pull to refresh ride status.'); });
  }

  Future<void> refreshRide(String id) async {
    try {
      final row = await Supabase.instance.client.from('rides').select().eq('id', id).maybeSingle();
      if (row == null || !mounted) return;
      final r = RideRecord.fromMap(row);
      setState(() { ride = r; lastSeq = r.sequence; });
      if (['completed', 'cancelled', 'failed'].contains(r.status)) { await eventSub?.cancel(); setState(() => notice = 'Ride ${r.status}.'); }
    } catch (_) {}
  }

  Future<void> cancelRide() async {
    final r = ride;
    if (r == null || busy) return;
    setState(() { busy = true; error = null; });
    try { final updated = await backend.cancelRide(r.id); if (mounted) setState(() { ride = updated; notice = 'Ride cancelled.'; }); await eventSub?.cancel(); }
    on PostgrestException catch (e) { if (mounted) setState(() => error = friendlyError(e.message)); }
    catch (_) { if (mounted) setState(() => error = 'Could not cancel. Refresh and try again.'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  void openCustomerSection(String section) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => section == 'account' ? AccountScreen() : section == 'settings' ? SettingsScreen() : section == 'history' ? HistoryScreen() : CustomerSectionScreen(section: section),
    ));
  }

  bool get isActive => ride != null && !['completed', 'cancelled', 'failed'].contains(ride!.status);
  Future<void> signOut() => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Go-Ride'),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Account and trips',
          onSelected: openCustomerSection,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history), title: Text('Ride history'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'saved', child: ListTile(leading: Icon(Icons.bookmark_outline), title: Text('Saved places'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'support', child: ListTile(leading: Icon(Icons.support_agent), title: Text('Customer support'), contentPadding: EdgeInsets.zero)),
            PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('My profile'), contentPadding: EdgeInsets.zero)),
          ],
        ),
        IconButton(tooltip: 'Sign out', onPressed: signOut, icon: const Icon(Icons.logout)),
      ],
    ),
    body: SafeArea(child: RefreshIndicator(onRefresh: () async { if (ride != null) { await refreshRide(ride!.id); } else { await locate(); } }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF087E72), borderRadius: BorderRadius.circular(22)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your ride, your time.', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
          SizedBox(height: 8), Text('Set your pickup, choose a fare, and request a ride.', style: TextStyle(color: Colors.white70)),
        ])),
      const SizedBox(height: 18),
      if (error != null) Message(text: error!, isError: true),
      if (notice != null) Message(text: notice!),
      ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 270,
          child: FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: ll.LatLng(pickup?.latitude ?? 25.89, pickup?.longitude ?? 81.99),
              initialZoom: 11,
              onTap: _mapTap,
            ),
            children: [
              TileLayer(urlTemplate: _tileUrl, additionalOptions: const {'accessToken': _mapboxToken}, userAgentPackageName: 'com.goride.customer', maxZoom: 19),
              if (routePoints.isNotEmpty)
                PolylineLayer(polylines: [Polyline(points: routePoints, color: Colors.white, strokeWidth: 5)]),
              MarkerLayer(markers: [
                if (pickup != null) Marker(
                  point: ll.LatLng(pickup!.latitude, pickup!.longitude),
                  width: 42, height: 42,
                  child: const Icon(Icons.trip_origin, color: Color(0xFFB9D5CE), size: 30),
                ),
                if (destination != null) Marker(
                  point: ll.LatLng(destination!.latitude, destination!.longitude),
                  width: 42, height: 42,
                  child: const Icon(Icons.location_pin, color: Colors.white, size: 40),
                ),
              ]),
              RichAttributionWidget(attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
                
              ]),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: locating ? null : locate,
          icon: const Icon(Icons.my_location),
          label: const Text('Use my location'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => setState(() {
            choosePickupOnMap = true;
            notice = 'Tap the map to choose your pickup.';
          }),
          icon: const Icon(Icons.touch_app),
          label: const Text('Set pickup on map'),
        )),
      ]),
      const SizedBox(height: 12),
      if (ride != null) ...[
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your ride status', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 8), Text(statusLabel(ride!.status), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const Divider(height: 28), Text('Ride ID: ${ride!.id.substring(0, ride!.id.length > 8 ? 8 : ride!.id.length)}'),
          const SizedBox(height: 6), Text('${ride!.category} · ${ride!.currency} ${(ride!.amountMinor / 100).toStringAsFixed(0)}'),
          const SizedBox(height: 6), const Text('Live status updates appear when a driver or dispatch system updates this ride.'),
        ]))),
        if (isActive && ['searching', 'driver_assigned', 'driver_arriving', 'driver_arrived'].contains(ride!.status))
          OutlinedButton.icon(onPressed: busy ? null : cancelRide, icon: const Icon(Icons.close), label: const Text('Cancel ride')),
        if (!isActive) FilledButton(onPressed: () => setState(() { ride = null; notice = null; error = null; }), child: const Text('Book another ride')),
      ] else ...[
        TextField(controller: pickupText, readOnly: true, decoration: InputDecoration(labelText: 'Pickup location', prefixIcon: const Icon(Icons.my_location),
          suffixIcon: IconButton(onPressed: locating ? null : locate, icon: locating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh)))),
        const SizedBox(height: 12),
        TextField(
          controller: destinationText,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Where to?', prefixIcon: Icon(Icons.location_on_outlined), hintText: 'Enter destination address'),
          onSubmitted: (_) => estimate(),
          onChanged: (_) {
            setState(() {
              destination = null;
              quotes = [];
              routePoints = [];
              notice = null;
            });
          },
        ),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: busy ? null : estimate, icon: const Icon(Icons.local_taxi), label: Text(busy ? 'Please wait…' : 'Get fares')),
        if (quotes.isNotEmpty) ...[
          const SizedBox(height: 20), Text('Choose your ride', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
          for (final q in quotes) Card(child: ListTile(
            leading: Icon(categoryIcon(q.category), size: 30), title: Text(q.category),
            subtitle: Text('Estimated arrival ${q.etaSeconds ~/ 60} min · quote valid for 2 minutes'),
            trailing: Text('${q.currency} ${(q.amountMinor / 100).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            onTap: busy ? null : () => book(q),
          )),
        ],
      ],
      const SizedBox(height: 18),
      const Text('Location is used to set your pickup and estimate the trip. Permission is requested only when needed.', style: TextStyle(color: Colors.black54, fontSize: 12)),
    ]))),
    bottomNavigationBar: NavigationBar(
      backgroundColor: const Color(0xFF151515),
      indicatorColor: const Color(0xFF343434),
      selectedIndex: 0,
      onDestinationSelected: (index) {
        if (index == 0) return;
        if (index == 1) {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const ServicesScreen()),
          );
          return;
        }
        if (index == 2 || index == 3) {
          Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (_) => CustomerSectionScreen(section: index == 2 ? 'history' : 'profile'),
          ));
        }
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Services'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Activity'),
        NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
      ],
    ),
  );

  String statusLabel(String status) => switch (status) {
    'searching' => 'Finding your driver', 'driver_assigned' => 'Driver assigned',
    'driver_arriving' => 'Driver on the way', 'driver_arrived' => 'Driver has arrived',
    'otp_required' => 'Confirm pickup with OTP', 'in_trip' => 'You are on your way',
    'completed' => 'Ride completed', 'cancelled' => 'Ride cancelled', 'failed' => 'Ride failed',
    _ => 'Ride status: $status',
  };
  IconData categoryIcon(String category) => switch (category.toUpperCase()) {
    'BIKE' => Icons.two_wheeler,
    'AUTO' => Icons.electric_rickshaw,
    'MINI' => Icons.directions_car_filled,
    'SEDAN' => Icons.local_taxi,
    _ => Icons.directions_car,
  };
}

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Services')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Choose a service',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Select a Go-Ride service to continue.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Icon(Icons.local_taxi_outlined)),
            title: const Text('Ride Booking'),
            subtitle: const Text('Book a ride and compare available vehicle types.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
            title: const Text('Parcel Delivery'),
            subtitle: const Text('Arrange a local pickup and delivery.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const ParcelScreen()),
            ),
          ),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Icon(Icons.restaurant_outlined)),
            title: const Text('Food Delivery'),
            subtitle: const Text('Coming soon'),
            trailing: const Icon(Icons.lock_outline),
            enabled: false,
          ),
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: const CircleAvatar(child: Icon(Icons.shopping_bag_outlined)),
            title: const Text('Shopping & Quick Commerce'),
            subtitle: const Text('Coming soon'),
            trailing: const Icon(Icons.lock_outline),
            enabled: false,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Only services marked as available can accept real bookings. Other services will be enabled after their backend workflows are ready.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class CustomerSectionScreen extends StatefulWidget {
  const CustomerSectionScreen({super.key, required this.section, this.backendReady = true});
  final String section;
  final bool backendReady;
  @override
  State<CustomerSectionScreen> createState() => _CustomerSectionScreenState();
}

class _CustomerSectionScreenState extends State<CustomerSectionScreen> {
  bool loading = true, saving = false;
  String? error, notice;
  List<Map<String, dynamic>> rows = [];
  final subject = TextEditingController();
  final message = TextEditingController();

  SupabaseClient get client => Supabase.instance.client;
  bool get isGuest => !widget.backendReady || client.auth.currentUser == null;
  String get title => switch (widget.section) {
    'history' => 'Ride history', 'rideHistory' => 'Ride history', 'parcelHistory' => 'Parcel history', 'saved' => 'Saved places', 'support' => 'Customer support', _ => 'My profile',
  };

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { subject.dispose(); message.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      if (!widget.backendReady) {
        if (mounted) setState(() => rows = []);
        return;
      }
      final user = client.auth.currentUser;
      // Guests can explore every section. Private account data is only queried
      // after authentication; guest screens show honest empty/preview states.
      if (user == null) {
        if (mounted) setState(() => rows = []);
        return;
      }
      dynamic result;
      if (widget.section == 'history' || widget.section == 'rideHistory') {
        result = await client.from('rides').select('id,status,category,fare_minor,currency,pickup_label,destination_label,created_at').eq('customer_id', user.id).order('created_at', ascending: false).limit(50);
      } else if (widget.section == 'saved') {
        result = await client.from('saved_places').select('id,label,address,latitude,longitude,created_at').eq('user_id', user.id).order('created_at', ascending: false).limit(100);
      } else if (widget.section == 'support') {
        result = await client.from('support_tickets').select('id,subject,message,status,needs_human,priority,ai_attempt_count,created_at').eq('user_id', user.id).order('created_at', ascending: false).limit(50);
      } else {
        result = await client.from('profiles').select('full_name,phone,avatar_url,created_at').eq('id', user.id).maybeSingle();
      }
      if (!mounted) return;
      setState(() { rows = result is List ? result.map((e) => Map<String,dynamic>.from(e as Map)).toList() : (result is Map<String,dynamic> ? [result] : []); });
    } catch (_) { if (mounted) setState(() => error = 'Could not load this section. Check your connection and account permissions.'); }
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> addSavedPlace() async {
    if (!widget.backendReady || client.auth.currentUser == null) {
      await requireSignIn();
      return;
    }
    final labelController = TextEditingController();
    final addressController = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Save a place'),
      content: SingleChildScrollView(child: Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:labelController,decoration:const InputDecoration(labelText:'Label',hintText:'Home, Work…')),
        const SizedBox(height:10),
        TextField(controller:addressController,decoration:const InputDecoration(labelText:'Address'),maxLines:2),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))],
    ));
    if (ok != true) { labelController.dispose(); addressController.dispose(); return; }
    try {
      final label=labelController.text.trim(), address=addressController.text.trim();
      if(label.isEmpty || address.isEmpty) throw Exception('Enter a label and address.');
      final matches=await locationFromAddress(address);
      if(matches.isEmpty) throw Exception('Address could not be located.');
      final user=client.auth.currentUser!;
      await client.from('saved_places').insert({'user_id':user.id,'label':label,'address':address,'latitude':matches.first.latitude,'longitude':matches.first.longitude});
      if(mounted) { setState(()=>notice='Place saved.'); await load(); }
    } catch (_) { if(mounted) setState(()=>error='Could not save that place. Check the address and try again.'); }
    finally { labelController.dispose(); addressController.dispose(); }
  }

  Future<void> deleteSavedPlace(String id) async {
    try {
      await client.from('saved_places').delete().eq('id',id).eq('user_id',client.auth.currentUser!.id);
      if(mounted) { setState(()=>notice='Saved place removed.'); await load(); }
    } catch (_) { if(mounted) setState(()=>error='Could not remove this saved place.'); }
  }

  Future<void> createTicket() async {
    if (!widget.backendReady || client.auth.currentUser == null) {
      await requireSignIn();
      return;
    }
    final s=subject.text.trim(), m=message.text.trim();
    if(s.isEmpty || m.isEmpty) { setState(()=>error='Enter a subject and describe the issue.'); return; }
    setState(()=>saving=true);
    try {
      final created = await client.from('support_tickets')
          .insert({'user_id':client.auth.currentUser!.id,'subject':s,'message':m})
          .select('id')
          .single();
      subject.clear(); message.clear();
      var messageText = 'Support request submitted. Open the ticket to continue.';
      try {
        final response = await client.functions.invoke('ai-support-agent', body: {
          'ticket_id': created['id'].toString(),
          'message': m,
        });
        final data = response.data;
        if (data is Map && data['status'] == 'escalated') {
          messageText = 'Your request has been submitted and escalated to human support.';
        } else if (data is Map && data['status'] == 'answered') {
          messageText = 'Your request has been submitted. Go-Ride support has replied.';
        }
      } catch (aiError) {
        debugPrint('AI support invocation failed; ticket remains in the Admin queue: $aiError');
        messageText = 'Support request submitted. If AI support is unavailable, the Admin team can still review your ticket.';
      }
      if(mounted) { setState(()=>notice=messageText); await load(); }
    } catch (_) { if(mounted) setState(()=>error='Support request could not be submitted. Please try again.'); }
    finally { if(mounted) setState(()=>saving=false); }
  }

  Future<void> requireSignIn() async {
    if (!widget.backendReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign-in is temporarily unavailable because backend configuration is missing.')));
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => LoginScreen(onSignedIn: () => Navigator.of(context).pop()),
    ));
    if (mounted && client.auth.currentUser != null) await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:Text(title),actions:[IconButton(onPressed:load,tooltip:'Refresh',icon:const Icon(Icons.refresh))]),
    floatingActionButton:widget.section=='saved'?FloatingActionButton.extended(onPressed:addSavedPlace,icon:const Icon(Icons.add_location_alt),label:const Text('Add place')):null,
    body:SafeArea(child:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:load,child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.all(16),children:[
      if (isGuest) Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.visibility_outlined, color: Color(0xFF087E72)),
              SizedBox(width: 8),
              Expanded(child: Text('Guest preview', style: TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 8),
            const Text('You can explore this screen without an account. Sign in is only needed for personal data or actions that save information.'),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(
              onPressed: requireSignIn,
              icon: const Icon(Icons.login),
              label: const Text('Sign in'),
            )),
          ]),
        ),
      ),
      if(error!=null) Message(text:error!,isError:true),
      if(notice!=null) Message(text:notice!),
      if(widget.section=='support') ...[
        const Text('Need help?',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        TextField(controller:subject,decoration:const InputDecoration(labelText:'Subject')),
        const SizedBox(height:10),
        TextField(controller:message,decoration:const InputDecoration(labelText:'Describe your issue'),minLines:3,maxLines:6),
        const SizedBox(height:10),
        FilledButton.icon(onPressed:saving?null:createTicket,icon:const Icon(Icons.send),label:Text(saving?'Submitting…':'Submit support request')),
        const Divider(height:32),
        const Text('Your requests',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      ],
      if(widget.section=='profile') ...[
        ListTile(leading:const Icon(Icons.person_outline),title:Text(rows.isNotEmpty && (rows.first['full_name']?.toString().isNotEmpty??false)?rows.first['full_name'].toString():'Go-Ride customer'),subtitle:Text(isGuest ? 'Guest preview · no account connected' : (client.auth.currentUser?.email ?? client.auth.currentUser?.phone ?? 'Signed-in account'))),
        ListTile(leading:const Icon(Icons.verified_user_outlined),title:const Text('Account authentication'),subtitle:Text(isGuest ? 'Sign in to view account authentication details' : (client.auth.currentUser?.appMetadata['provider']?.toString() ?? 'Supabase Auth'))),
        const Padding(padding:EdgeInsets.all(12),child:Text('Profile editing and account deletion require a dedicated verified workflow; no destructive account action is exposed here.')),
      ],
      if(rows.isEmpty && widget.section!='profile' && widget.section!='account') Padding(padding:const EdgeInsets.symmetric(vertical:32),child:Column(children:[
        const Icon(Icons.inbox_outlined,size:48,color:Colors.black38),
        const SizedBox(height:8),
        Text(isGuest
          ? (widget.section == 'history' ? 'Your rides will appear here after you sign in and book.' : widget.section == 'saved' ? 'Sign in to save and manage your places.' : 'Sign in to view and submit your support requests.')
          : 'Nothing here yet.'),
      ])),
      for(final row in rows) if(widget.section=='history' || widget.section=='rideHistory') Card(child:ListTile(
        leading:const Icon(Icons.local_taxi,color:Color(0xFF087E72)),
        title:Text('${row['category'] ?? 'Ride'} · ${row['status'] ?? 'unknown'}'),
        subtitle:Text('${row['pickup_label'] ?? 'Pickup'} → ${row['destination_label'] ?? 'Destination'}\n${row['created_at'] ?? ''}',maxLines:3,overflow:TextOverflow.ellipsis),
        trailing:Text('${row['currency'] ?? 'INR'} ${(((row['fare_minor'] as num?)?.toInt() ?? 0)/100).toStringAsFixed(0)}'),
      )),
      for(final row in rows) if(widget.section=='saved') Card(child:ListTile(
        leading:const Icon(Icons.bookmark_outline,color:Color(0xFF087E72)),
        title:Text(row['label']?.toString() ?? 'Saved place'),
        subtitle:Text(row['address']?.toString() ?? ''),
        trailing:IconButton(tooltip:'Delete saved place',onPressed:()=>deleteSavedPlace(row['id'].toString()),icon:const Icon(Icons.delete_outline)),
      )),
      for(final row in rows) if(widget.section=='support') Card(child:ListTile(
        leading:Icon(row['needs_human'] == true ? Icons.support_agent : Icons.chat_bubble_outline,color:row['priority'] == 'urgent' ? Colors.red : const Color(0xFF087E72)),
        title:Text(row['subject']?.toString() ?? 'Support request'),
        subtitle:Text('${row['message'] ?? ''}\nStatus: ${row['status'] ?? 'open'} · Priority: ${row['priority'] ?? 'normal'}${row['needs_human'] == true ? ' · Human support' : ''}',maxLines:4,overflow:TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => SupportTicketChatScreen(ticketId: row['id'].toString(), subject: row['subject']?.toString() ?? 'Support request'),
        )),
      )),
    ]))),
  );
}


class SupportTicketChatScreen extends StatefulWidget {
  const SupportTicketChatScreen({super.key, required this.ticketId, required this.subject});
  final String ticketId;
  final String subject;

  @override
  State<SupportTicketChatScreen> createState() => _SupportTicketChatScreenState();
}

class _SupportTicketChatScreenState extends State<SupportTicketChatScreen> {
  final TextEditingController _message = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _needsHuman = false;
  String _status = 'open';
  String? _error;
  String? _notice;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _client.from('support_ticket_messages')
            .select('id,author_type,content,created_at')
            .eq('ticket_id', widget.ticketId)
            .order('created_at'),
        _client.from('support_tickets')
            .select('status,needs_human')
            .eq('id', widget.ticketId)
            .maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(results[0] as List);
        final ticket = results[1] as Map<String, dynamic>?;
        _status = ticket?['status']?.toString() ?? 'open';
        _needsHuman = ticket?['needs_human'] == true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load this conversation. Refresh and try again.');
      debugPrint('Support conversation load failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send({bool requestHuman = false}) async {
    final content = requestHuman ? 'Please connect me to a human support agent.' : _message.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() { _sending = true; _error = null; _notice = null; });
    try {
      final response = await _client.functions.invoke('ai-support-agent', body: {
        'ticket_id': widget.ticketId,
        'message': content,
        'request_human': requestHuman,
      });
      if (response.status >= 400) throw Exception('support_function_failed');
      _message.clear();
      final data = response.data;
      if (mounted) {
        setState(() => _notice = data is Map && data['status'] == 'escalated'
            ? 'Your conversation has been escalated to human support.'
            : 'Go-Ride support has replied.');
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = 'Message could not be sent. Your original ticket is still saved and visible to the Admin team.');
      debugPrint('Support message send failed: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.subject), actions: [
          IconButton(onPressed: _loading ? null : _load, tooltip: 'Refresh conversation', icon: const Icon(Icons.refresh)),
        ]),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: _needsHuman ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Text(
                  'Status: ' + _status + (_needsHuman ? ' · Human support requested' : ''),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Message(text: _error!, isError: true)),
              if (_notice != null) Padding(padding: const EdgeInsets.all(8), child: Message(text: _notice!)),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_messages.isEmpty) const Text('Send a message to start this support conversation.'),
                          for (final item in _messages)
                            Align(
                              alignment: item['author_type'] == 'customer' ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 560),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: item['author_type'] == 'customer'
                                      ? Theme.of(context).colorScheme.primaryContainer
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['author_type'] == 'customer' ? 'You'
                                          : item['author_type'] == 'ai_agent' ? 'Go-Ride AI support'
                                          : item['author_type'] == 'admin' ? 'Go-Ride support team'
                                          : 'System update',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(item['content']?.toString() ?? ''),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _message,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Reply to support', border: OutlineInputBorder()),
                      enabled: !_sending && _status != 'closed' && _status != 'resolved',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _sending || _status == 'closed' || _status == 'resolved' ? null : () => _send(requestHuman: true),
                          icon: const Icon(Icons.support_agent),
                          label: const Text('Human support'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _sending || _status == 'closed' || _status == 'resolved' ? null : () => _send(),
                          icon: const Icon(Icons.send),
                          label: Text(_sending ? 'Sending…' : 'Send'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, this.backendReady = true});
  final bool backendReady;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('History')), body: ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: ListTile(leading: const Icon(Icons.local_taxi), title: const Text('Ride History'), subtitle: const Text('Previous rides, fares and statuses'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => CustomerSectionScreen(section: 'rideHistory', backendReady: backendReady))))),
    Card(child: ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Parcel History'), subtitle: const Text('Sent and received parcels'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ParcelHistoryScreen())))),
  ]));
}
class ParcelScreen extends StatelessWidget {
  const ParcelScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Parcel')), body: ListView(padding: const EdgeInsets.all(16), children: [
    Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFFF2E5DF), borderRadius: BorderRadius.circular(22)), child: const Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Send anything, anywhere', style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.bold)), SizedBox(height: 6), Text('Safe, simple local delivery', style: TextStyle(color: Colors.black87))])), Icon(Icons.inventory_2, size: 54, color: Colors.black87)])),
    const SizedBox(height: 16),
    Card(child: ListTile(leading: const Icon(Icons.outbox_outlined), title: const Text('Send Parcel'), subtitle: const Text('Send a parcel to another person or address'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ParcelRequestScreen(mode: 'Send Parcel'))))),
    Card(child: ListTile(leading: const Icon(Icons.move_to_inbox_outlined), title: const Text('Receive Parcel'), subtitle: const Text('Arrange to receive a parcel from someone'), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ParcelRequestScreen(mode: 'Receive Parcel'))))),
    const Padding(padding: EdgeInsets.only(top: 20, bottom: 8), child: Text('Other parcel services', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
    for (final item in const [('Same-day delivery', Icons.rocket_launch_outlined), ('Scheduled pickup', Icons.calendar_month_outlined), ('Bulk / business delivery', Icons.inventory_outlined), ('Fragile items', Icons.wine_bar_outlined), ('Track parcel', Icons.location_searching_outlined)])
      Card(child: ListTile(leading: Icon(item.$2), title: Text(item.$1), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => item.$1 == 'Track parcel' ? const ParcelHistoryScreen() : ParcelRequestScreen(mode: item.$1))))),
    const Padding(padding: EdgeInsets.only(top: 12), child: Text('Parcel requests are not yet connected to a live delivery backend. No real order is submitted from this screen.', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12))),
  ]));
}
class ParcelRequestScreen extends StatefulWidget {
  const ParcelRequestScreen({super.key, required this.mode});
  final String mode;
  @override
  State<ParcelRequestScreen> createState() => _ParcelRequestScreenState();
}
class _ParcelRequestScreenState extends State<ParcelRequestScreen> {
  final pickup = TextEditingController(), destination = TextEditingController(), details = TextEditingController(), phone = TextEditingController();
  @override
  void dispose() { pickup.dispose(); destination.dispose(); details.dispose(); phone.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.mode)), body: ListView(padding: const EdgeInsets.all(16), children: [
    TextField(controller: pickup, decoration: const InputDecoration(labelText: 'Pickup location', prefixIcon: Icon(Icons.trip_origin))),
    const SizedBox(height: 12), TextField(controller: destination, decoration: const InputDecoration(labelText: 'Delivery / sender location', prefixIcon: Icon(Icons.location_on_outlined))),
    const SizedBox(height: 12), TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact mobile number', prefixIcon: Icon(Icons.phone))),
    const SizedBox(height: 12), TextField(controller: details, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Parcel description, size and instructions')),
    const SizedBox(height: 20), FilledButton(onPressed: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Parcel booking not live yet'), content: const Text('Your details have not been sent or saved. Parcel booking requires a secured backend and delivery operations before accepting real orders.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))])), child: const Text('Continue')),
  ]));
}
class ParcelHistoryScreen extends StatelessWidget {
  const ParcelHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Parcel History')), body: const Center(child: Padding(padding: EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inventory_2_outlined, size: 52), SizedBox(height: 12), Text('No parcel history yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), SizedBox(height: 8), Text('Parcel history will be available when parcel bookings are connected to the backend.', textAlign: TextAlign.center)]))));
}
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.backendReady = true});
  final bool backendReady;
  @override
  Widget build(BuildContext context) {
    void open(String section) => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => section == 'settings' ? SettingsScreen(backendReady: backendReady) : section == 'history' ? HistoryScreen(backendReady: backendReady) : section == 'signin' ? LoginScreen() : CustomerSectionScreen(section: section, backendReady: backendReady)));
    final signedIn = backendReady && Supabase.instance.client.auth.currentUser != null;
    final items = <(String, IconData, String)>[
      ('My Profile', Icons.person_outline, 'profile'), ('History', Icons.history, 'history'), ('Saved Places', Icons.place_outlined, 'saved'), ('Payment Methods', Icons.credit_card_outlined, 'payments'), ('Help & Support', Icons.support_agent, 'support'), ('Settings', Icons.settings_outlined, 'settings'), ('Privacy Policy', Icons.privacy_tip_outlined, 'privacy'), ('Terms & Conditions', Icons.description_outlined, 'terms'), ('About Go-Ride', Icons.info_outline, 'about'),
    ];
    return Scaffold(appBar: AppBar(title: const Text('Account')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.person)), title: Text(signedIn ? (Supabase.instance.client.auth.currentUser?.phone ?? Supabase.instance.client.auth.currentUser?.email ?? 'Go-Ride customer') : 'Guest User'), subtitle: Text(signedIn ? 'Manage your Go-Ride account' : 'Explore Go-Ride without signing in'), trailing: const Icon(Icons.chevron_right), onTap: () => open(signedIn ? 'profile' : 'signin'))),
      if (!signedIn) Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: FilledButton.icon(onPressed: () => open('signin'), icon: const Icon(Icons.login), label: const Text('Log in / Sign up'))),
      for (final item in items) ListTile(leading: Icon(item.$2), title: Text(item.$1), trailing: const Icon(Icons.chevron_right), onTap: () => item.$3 == 'privacy' || item.$3 == 'terms' || item.$3 == 'about' ? showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text(item.$1), content: Text(item.$3 == 'privacy' ? 'Publish a reviewed privacy policy before public launch.' : item.$3 == 'terms' ? 'Terms and conditions must be reviewed and published before public launch.' : 'Go-Ride is a local ride and parcel service in development.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))])) : open(item.$3)),
      const Divider(),
      if (signedIn) OutlinedButton.icon(onPressed: () async { await Supabase.instance.client.auth.signOut(); if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst); }, icon: const Icon(Icons.logout), label: const Text('Log out')),
    ]));
  }
}
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.backendReady = true});
  final bool backendReady;
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}
class _SettingsScreenState extends State<SettingsScreen> {
  String language = 'English', payment = 'Cash';
  bool notifications = true, location = true;
  final methods = const ['Cash', 'UPI', 'Debit/Credit card', 'Go-Ride wallet'];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final p = await SharedPreferences.getInstance(); if (!mounted) return; setState(() { payment=p.getString('go_ride_payment')??'Cash'; language=p.getString('go_ride_language')??'English'; notifications=p.getBool('go_ride_notifications')??true; location=p.getBool('go_ride_location')??true; }); } catch (_) {}
  }
  Future<void> _saveString(String k,String v) async { try { final p=await SharedPreferences.getInstance(); await p.setString(k,v); } catch (_) {} }
  Future<void> _saveBool(String k,bool v) async { try { final p=await SharedPreferences.getInstance(); await p.setBool(k,v); } catch (_) {} }
  Future<void> _setTheme(ThemeMode mode) async {
    appThemeMode.value=mode;
    try { final p=await SharedPreferences.getInstance(); await p.setString('go_ride_theme',switch(mode){ThemeMode.light=>'light',ThemeMode.system=>'system',ThemeMode.dark=>'dark'}); } catch (_) {}
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings')), body: ListView(padding: const EdgeInsets.all(16), children: [
    const Text('Appearance',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    Card(child: Column(children:[
      RadioListTile<ThemeMode>(value:ThemeMode.system,groupValue:appThemeMode.value,onChanged:(v){if(v!=null)_setTheme(v);},title:const Text('System default'),subtitle:const Text('Match your phone settings'),secondary:const Icon(Icons.brightness_auto_outlined)),
      RadioListTile<ThemeMode>(value:ThemeMode.light,groupValue:appThemeMode.value,onChanged:(v){if(v!=null)_setTheme(v);},title:const Text('Light'),secondary:const Icon(Icons.light_mode_outlined)),
      RadioListTile<ThemeMode>(value:ThemeMode.dark,groupValue:appThemeMode.value,onChanged:(v){if(v!=null)_setTheme(v);},title:const Text('Dark'),secondary:const Icon(Icons.dark_mode_outlined)),
    ])),
    const SizedBox(height:16),const Text('Preferences',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    ListTile(leading:const Icon(Icons.language),title:const Text('Language'),trailing:DropdownButton<String>(value:language,items:const[DropdownMenuItem(value:'English',child:Text('English')),DropdownMenuItem(value:'हिन्दी',child:Text('हिन्दी'))],onChanged:(v){if(v!=null){setState(()=>language=v);_saveString('go_ride_language',v);}})),
    const SizedBox(height:16),const Text('Payment preferences',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const Text('Select a preferred method. You can review it again before booking.',style:TextStyle(color:Color(0xFF999999))),
    for(final method in methods) Card(margin:const EdgeInsets.only(top:8),child:RadioListTile<String>(
      value:method,groupValue:payment,onChanged:(v){if(v!=null){setState(()=>payment=v);_saveString('go_ride_payment',v);}},
      title:Text(method),subtitle:Text(switch(method){'Cash'=>'Pay the driver directly after the ride','UPI'=>'BHIM, Google Pay, PhonePe and other UPI apps','Debit/Credit card'=>'Requires a secure payment provider',_=>'Wallet top-ups are not available yet'}),
      secondary:Icon(switch(method){'Cash'=>Icons.payments_outlined,'UPI'=>Icons.qr_code_2,'Debit/Credit card'=>Icons.credit_card_outlined,_=>Icons.account_balance_wallet_outlined}),
    )),
    if(payment!='Cash') Padding(padding:const EdgeInsets.only(top:8),child:Message(text:payment=='Go-Ride wallet'?'Wallet is a planned option only; no balance or payment will be charged.':'This preference is saved only. Online payments are not active until a verified payment provider is integrated.')),
    const Divider(height:32),const Text('App controls',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    SwitchListTile(value:notifications,onChanged:(v){setState(()=>notifications=v);_saveBool('go_ride_notifications',v);},secondary:const Icon(Icons.notifications_outlined),title:const Text('Notifications')),
    SwitchListTile(value:location,onChanged:(v){setState(()=>location=v);_saveBool('go_ride_location',v);},secondary:const Icon(Icons.location_on_outlined),title:const Text('Location services'),subtitle:const Text('This preference does not replace Android permissions')),
    const Divider(height:32),const Text('Account security',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    ExpansionTile(leading:const Icon(Icons.delete_forever_outlined,color:Colors.red),title:const Text('Delete Account',style:TextStyle(color:Colors.red)),subtitle:const Text('Account removal options'),children:const[Padding(padding:EdgeInsets.all(16),child:Text('Account deletion is not enabled until a verified server-side workflow can safely remove or anonymize personal data.'))]),
    const Padding(padding:EdgeInsets.all(12),child:Text('Theme and preferences are saved on this device. Language is saved, but full translation depends on localization support. Payment processing is not enabled by these settings.',style:TextStyle(fontSize:12,color:Color(0xFF999999)))),
  ]));
}

class BookingReviewScreen extends StatelessWidget {
  const BookingReviewScreen({super.key,required this.pickupLabel,required this.destinationLabel,required this.category,required this.amountMinor,required this.currency,required this.distanceKm,required this.etaSeconds,required this.backendReady});
  final String pickupLabel,destinationLabel,category,currency;
  final int amountMinor,etaSeconds; final double distanceKm; final bool backendReady;
  @override Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('Review your booking')),body:ListView(padding:const EdgeInsets.all(16),children:[
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('YOUR TRIP',style:TextStyle(fontSize:12,letterSpacing:1.2,color:Color(0xFF999999))),const SizedBox(height:14),
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.radio_button_checked,color:Color(0xFFB9D5CE)),const SizedBox(width:12),Expanded(child:Text(pickupLabel))]),
      const Padding(padding:EdgeInsets.only(left:5),child:SizedBox(height:26,child:VerticalDivider(width:1))),
      Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.location_on,color:Colors.redAccent),const SizedBox(width:12),Expanded(child:Text(destinationLabel))]),
      const Divider(height:28),
      ListTile(contentPadding:EdgeInsets.zero,leading:Icon(category=='BIKE'?Icons.two_wheeler:category=='AUTO'?Icons.electric_rickshaw:Icons.directions_car),title:Text(category),subtitle:Text('${distanceKm.toStringAsFixed(1)} km · \${(etaSeconds/60).ceil()} min'),trailing:Text('$currency \${(amountMinor/100).toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18))),
    ]))),
    const SizedBox(height:8),Card(child:ListTile(leading:const Icon(Icons.payments_outlined),title:const Text('Payment method'),subtitle:const Text('Review your preferred method in Settings before confirming.'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.of(context).push<void>(MaterialPageRoute<void>(builder:(_)=>const SettingsScreen())))),
    const SizedBox(height:12),const Message(text:'No ride is requested yet. Review the trip, then sign in to continue to live booking.'),
    const SizedBox(height:12),FilledButton.icon(onPressed:!backendReady?null:()=>Navigator.of(context).push<void>(MaterialPageRoute<void>(builder:(_)=>LoginScreen(onSignedIn:(){Navigator.of(context).popUntil((route)=>route.isFirst);}))),icon:const Icon(Icons.login),label:const Text('Sign in to continue')),
    TextButton(onPressed:()=>Navigator.of(context).pop(),child:const Text('Change trip details')),
  ]));
}

class Message extends StatelessWidget {
  const Message({super.key, required this.text, this.isError = false});
  final String text;
  final bool isError;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: isError ? Colors.red.shade50 : Colors.teal.shade50, borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: TextStyle(color: isError ? Colors.red.shade900 : Colors.teal.shade900)),
  );
}
