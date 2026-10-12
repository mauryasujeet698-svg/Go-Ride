import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_config.dart';
import 'data/ride_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Go-Ride',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087E72)),
      scaffoldBackgroundColor: const Color(0xFFF5F7F8),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
    ),
    home: AuthGate(backendReady: backendReady),
  );
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
  static const _tileUrl = String.fromEnvironment('OSM_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  static const _nominatim = String.fromEnvironment('GEOCODER_URL', defaultValue: 'https://nominatim.openstreetmap.org');
  static const _osrm = String.fromEnvironment('ROUTING_URL', defaultValue: 'https://router.project-osrm.org');
  final pickup = TextEditingController();
  final destination = TextEditingController();
  final mapController = MapController();
  GeoPoint? pickupPoint, destinationPoint;
  List<ll.LatLng> route = [];
  List<GuestFare> fares = [];
  bool busy = false, locating = false, choosePickup = false;
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
      final uri = Uri.parse('$_nominatim/search').replace(queryParameters: {'q': query, 'format':'jsonv2', 'limit':'5', 'addressdetails':'1'});
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

  Future<void> getRouteAndFares() async {
    final a = pickupPoint, b = destinationPoint;
    if (a == null || b == null) { setState(() => error = 'Set both pickup and destination first.'); return; }
    setState(() { busy = true; error = null; info = null; fares = []; });
    try {
      final uri = Uri.parse('$_osrm/route/v1/driving/${a.longitude},${a.latitude};${b.longitude},${b.latitude}').replace(queryParameters: {'overview':'full','geometries':'geojson','steps':'false'});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Route service is unavailable. Try again later or choose locations on the map.');
      final data = jsonDecode(response.body) as Map<String,dynamic>;
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
        final rows = await Supabase.instance.client.rpc('estimate_guest_fares', params: {'p_distance_km':km, 'p_eta_seconds':secs});
        quotes = (rows as List).map((x) { final m=Map<String,dynamic>.from(x as Map); return GuestFare(category:m['category'].toString(), amountMinor:(m['amount_minor'] as num).toInt(), currency:m['currency'].toString().trim(), etaSeconds:(m['eta_seconds'] as num).toInt()); }).toList();
      }
      if (!mounted) return;
      setState(() { route=points; distanceKm=km; routeSeconds=secs; fares=quotes; info=quotes.isEmpty ? 'Route found. Fare estimates are temporarily unavailable; no prices have been invented.' : 'Route and estimates use configured services. Booking will revalidate the fare after sign-in.'; });
      if (points.isNotEmpty) mapController.fitCamera(CameraFit.bounds(bounds: ll.LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(44)));
    } catch (e) { if (mounted) setState(() => error=e.toString().replaceFirst('Exception: ','')); }
    finally { if (mounted) setState(() => busy=false); }
  }

  Future<void> book(GuestFare fare) async {
    PendingBooking.pickup=pickupPoint; PendingBooking.destination=destinationPoint;
    PendingBooking.pickupLabel=pickup.text.trim(); PendingBooking.destinationLabel=destination.text.trim(); PendingBooking.category=fare.category;
    if (!widget.backendReady) { setState(() => error='Sign-in and booking are unavailable until backend configuration is restored.'); return; }
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => LoginScreen(onSignedIn: () => Navigator.of(context).pop())));
  }

  @override
  Widget build(BuildContext context) {
    final center = pickupPoint != null ? ll.LatLng(pickupPoint!.latitude,pickupPoint!.longitude) : const ll.LatLng(20.5937,78.9629);
    return Scaffold(
      appBar: AppBar(title: const Text('Go-Ride'), actions: [Padding(padding: const EdgeInsets.only(right:12), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal:10,vertical:6), decoration: BoxDecoration(color:Colors.teal.shade50,borderRadius:BorderRadius.circular(30)), child: const Text('EXPLORE',style:TextStyle(fontSize:10,fontWeight:FontWeight.bold,color:Color(0xFF087E72)))))]),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Where would you like to go?',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
        const SizedBox(height:6),
        const Text('Explore routes and fare estimates without signing in. Sign-in is required only to request a real ride.'),
        const SizedBox(height:14),
        ClipRRect(borderRadius:BorderRadius.circular(18), child:SizedBox(height:300, child: FlutterMap(mapController:mapController, options:MapOptions(initialCenter:center,initialZoom:4,onTap:_mapTap), children:[
          TileLayer(urlTemplate:_tileUrl,userAgentPackageName:'com.goride.customer', maxZoom:19),
          if (route.isNotEmpty) PolylineLayer(polylines:[Polyline(points:route,color:const Color(0xFF087E72),strokeWidth:5)]),
          MarkerLayer(markers:[
            if(pickupPoint!=null) Marker(point:ll.LatLng(pickupPoint!.latitude,pickupPoint!.longitude),width:42,height:42,child:const Icon(Icons.trip_origin,color:Color(0xFF087E72),size:32)),
            if(destinationPoint!=null) Marker(point:ll.LatLng(destinationPoint!.latitude,destinationPoint!.longitude),width:42,height:42,child:const Icon(Icons.location_pin,color:Colors.red,size:40)),
          ]),
          RichAttributionWidget(attributions:[TextSourceAttribution('© OpenStreetMap contributors')]),
        ]))),
        const SizedBox(height:8),
        Row(children:[Expanded(child:OutlinedButton.icon(onPressed:locating?null:locatePickup,icon:locating?const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.my_location),label:const Text('Use my location'))),const SizedBox(width:8),Expanded(child:OutlinedButton.icon(onPressed:()=>setState(()=>choosePickup=true),icon:const Icon(Icons.touch_app),label:const Text('Tap map to set pickup')))]),
        const SizedBox(height:12),
        TextField(controller:pickup,textCapitalization:TextCapitalization.words,decoration:InputDecoration(labelText:'Pickup location',prefixIcon:const Icon(Icons.trip_origin),suffixIcon:IconButton(tooltip:'Search pickup',onPressed:busy?null:()=>searchAddress(forPickup:true),icon:const Icon(Icons.search))),onSubmitted:(_)=>searchAddress(forPickup:true)),
        const SizedBox(height:10),
        TextField(controller:destination,textCapitalization:TextCapitalization.words,decoration:InputDecoration(labelText:'Destination',hintText:'Search address or tap map',prefixIcon:const Icon(Icons.location_on_outlined),suffixIcon:IconButton(tooltip:'Search destination',onPressed:busy?null:()=>searchAddress(forPickup:false),icon:const Icon(Icons.search))),onSubmitted:(_)=>searchAddress(forPickup:false)),
        const SizedBox(height:12),
        FilledButton.icon(onPressed:busy?null:getRouteAndFares,icon:busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.route),label:Text(busy?'Finding route…':'Show route and fares')),
        if(error!=null) Message(text:error!,isError:true),
        if(info!=null) Message(text:info!),
        if(distanceKm!=null) Card(child:ListTile(leading:const Icon(Icons.route,color:Color(0xFF087E72)),title:Text('${distanceKm!.toStringAsFixed(1)} km by road'),subtitle:Text('Estimated travel time ${((routeSeconds??0)/60).ceil()} min'))),
        if(fares.isNotEmpty) ...[
          const SizedBox(height:6),const Text('Choose a ride',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
          for(final fare in fares) Card(child:ListTile(
            leading:Icon(fare.category=='AUTO'?Icons.electric_rickshaw:fare.category=='MINI'?Icons.directions_car_filled:Icons.local_taxi,color:const Color(0xFF087E72),size:30),
            title:Text(fare.category),subtitle:Text('Estimated · ${((fare.etaSeconds)/60).ceil()} min · route ${distanceKm!.toStringAsFixed(1)} km'),
            trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text('${fare.currency} ${(fare.amountMinor/100).toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),const Text('Book',style:TextStyle(color:Color(0xFF087E72)))]),
            onTap:()=>book(fare),
          )),
        ],
        const SizedBox(height:12),
        const Text('Map data © OpenStreetMap contributors. Public map, routing and address-search endpoints are development defaults, not guaranteed production infrastructure.',style:TextStyle(fontSize:11,color:Colors.black54)),
      ])),
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
  final pickupText = TextEditingController();
  final destinationText = TextEditingController();
  final backend = RideBackend(Supabase.instance.client);
  GeoPoint? pickup, destination;
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
  void dispose() { eventSub?.cancel(); pickupText.dispose(); destinationText.dispose(); super.dispose(); }

  Future<void> restoreRide() async {
    try { final r = await backend.activeRide(); if (!mounted || r == null) return; setState(() => ride = r); watchRide(r); }
    catch (_) { if (mounted) setState(() => notice = 'Could not restore the previous ride.'); }
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

  bool get isActive => ride != null && !['completed', 'cancelled', 'failed'].contains(ride!.status);
  Future<void> signOut() => Supabase.instance.client.auth.signOut();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Go-Ride'), actions: [IconButton(tooltip: 'Sign out', onPressed: signOut, icon: const Icon(Icons.logout))]),
    body: SafeArea(child: RefreshIndicator(onRefresh: () async { if (ride != null) { await refreshRide(ride!.id); } else { await locate(); } }, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF087E72), borderRadius: BorderRadius.circular(22)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your ride, your time.', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
          SizedBox(height: 8), Text('Set your pickup, choose a fare, and request a ride.', style: TextStyle(color: Colors.white70)),
        ])),
      const SizedBox(height: 18),
      if (error != null) Message(text: error!, isError: true),
      if (notice != null) Message(text: notice!),
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
        TextField(controller: destinationText, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Where to?', prefixIcon: Icon(Icons.location_on_outlined), hintText: 'Enter destination address')),
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
  );

  String statusLabel(String status) => switch (status) {
    'searching' => 'Finding your driver', 'driver_assigned' => 'Driver assigned',
    'driver_arriving' => 'Driver on the way', 'driver_arrived' => 'Driver has arrived',
    'otp_required' => 'Confirm pickup with OTP', 'in_trip' => 'You are on your way',
    'completed' => 'Ride completed', 'cancelled' => 'Ride cancelled', 'failed' => 'Ride failed',
    _ => 'Ride status: $status',
  };
  IconData categoryIcon(String category) => switch (category.toUpperCase()) {
    'AUTO' => Icons.electric_rickshaw, 'MINI' => Icons.directions_car_filled, 'SEDAN' => Icons.local_taxi, _ => Icons.directions_car,
  };
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
