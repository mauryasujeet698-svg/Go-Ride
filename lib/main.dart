import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/app_config.dart';
import 'data/ride_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );
  runApp(const GoRideApp());
}

class GoRideApp extends StatelessWidget {
  const GoRideApp({super.key});
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
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, snapshot) => Supabase.instance.client.auth.currentSession == null
      ? const LoginScreen() : const RideHomeScreen(),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
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
  void dispose() { phone.dispose(); otp.dispose(); super.dispose(); }
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
  void initState() { super.initState(); restoreRide(); locate(); }
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
      final places = await locationFromAddress(destinationText.text.trim());
      if (places.isEmpty) throw Exception('Could not find that address. Try a fuller destination.');
      destination = GeoPoint(places.first.latitude, places.first.longitude);
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
