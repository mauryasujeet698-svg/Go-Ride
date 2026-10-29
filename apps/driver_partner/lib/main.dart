import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  }
  runApp(const DriverPartnerApp());
}

class DriverPartnerApp extends StatelessWidget {
  const DriverPartnerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Go-Ride Driver Partner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B46)),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: supabaseUrl.isEmpty || supabasePublishableKey.isEmpty
            ? const _ConfigurationPage()
            : const _DriverPage(),
      );
}

class _ConfigurationPage extends StatelessWidget {
  const _ConfigurationPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Go-Ride Driver Partner\n\nConfigure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY at build time. Never put a service-role key in this app.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

class _DriverPage extends StatefulWidget {
  const _DriverPage();

  @override
  State<_DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<_DriverPage> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _name = TextEditingController();
  final _vehicle = TextEditingController();
  final _registration = TextEditingController();

  String _category = 'BIKE';
  String _message = '';
  bool _busy = false;
  bool _isDriver = false;
  bool _isAvailable = false;
  String? _areaId;
  String _businessModel = 'subscription';
  List<Map<String, dynamic>> _areas = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _subscriptions = [];
  List<Map<String, dynamic>> _rides = [];
  Map<String, dynamic>? _application;

  SupabaseClient get _db => Supabase.instance.client;
  bool get _signedIn => _db.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    if (_signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(_refresh));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() { _busy = true; _message = ''; });
    try {
      await action();
    } catch (error) {
      _message = 'Could not complete this action. Check the details and backend configuration.';
      debugPrint('Driver app action failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOtp() => _run(() async {
        await _db.auth.signInWithOtp(phone: _phone.text.trim());
        _message = 'OTP requested. Enter the code sent to your phone.';
      });

  Future<void> _verifyOtp() => _run(() async {
        await _db.auth.verifyOTP(
          phone: _phone.text.trim(),
          token: _otp.text.trim(),
          type: OtpType.sms,
        );
        await _refresh();
      });

  Future<void> _refresh() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      _isDriver = false;
      _application = null;
      return;
    }

    final roles = await _db.from('user_roles')
        .select('role,status,revoked_at')
        .eq('user_id', user.id)
        .eq('role', 'driver')
        .eq('status', 'active')
        .isFilter('revoked_at', null);
    _isDriver = (roles as List).isNotEmpty;

    final applications = await _db.from('driver_applications')
        .select('id,status,review_note,created_at,vehicle_category,vehicle_make_model,vehicle_registration')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(1);
    _application = (applications as List).isEmpty
        ? null
        : Map<String, dynamic>.from((applications as List).first);

    if (!_isDriver) {
      _areas = [];
      _plans = [];
      _subscriptions = [];
      _rides = [];
      _areaId = null;
      return;
    }

    final areaRows = await _db.from('service_areas')
        .select('id,code,name,city,pincode,active')
        .eq('active', true)
        .order('code');
    _areas = List<Map<String, dynamic>>.from(areaRows);
    if (_areas.isNotEmpty && (_areaId == null || !_areas.any((a) => a['id'].toString() == _areaId))) {
      _areaId = _areas.first['id'].toString();
    }
    if (_areaId != null) {
      final setting = await _db.from('area_business_settings')
          .select('business_model,active')
          .eq('area_id', _areaId!)
          .eq('service', 'ride')
          .maybeSingle();
      _businessModel = setting?['business_model']?.toString() ?? 'disabled';
      final plans = await _db.from('subscription_plans')
          .select('id,name,description,price_minor,currency,duration_minutes,active')
          .eq('area_id', _areaId!)
          .eq('active', true)
          .order('price_minor');
      _plans = List<Map<String, dynamic>>.from(plans);
    } else {
      _plans = [];
    }

    final subs = await _db.from('driver_subscriptions')
        .select('id,area_id,plan_id,status,price_minor_snapshot,currency,starts_at,expires_at,duration_minutes_snapshot')
        .eq('driver_id', user.id)
        .order('created_at', ascending: false)
        .limit(20);
    _subscriptions = List<Map<String, dynamic>>.from(subs);

    final rides = await _db.from('rides')
        .select('id,status,category,fare_minor,currency,pickup_label,destination_label,created_at')
        .eq('driver_id', user.id)
        .inFilter('status', ['driver_assigned','driver_arriving','driver_arrived','in_trip'])
        .order('created_at', ascending: false)
        .limit(20);
    _rides = List<Map<String, dynamic>>.from(rides);
    final profile = await _db.from('driver_profiles').select('status').eq('user_id', user.id).maybeSingle();
    _isAvailable = profile?['status'] == 'available';
  }

  Future<void> _submitApplication() async {
    await _run(() async {
      final user = _db.auth.currentUser;
      if (user == null) throw StateError('Please verify your phone first.');
      final existing = await _db.from('driver_applications')
          .select('id,status')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1);
      if ((existing as List).isNotEmpty) {
        final status = existing.first['status']?.toString() ?? 'pending';
        if (status != 'rejected') {
          _message = 'Your latest application status is ' + status + '. You do not need to submit another application.';
          return;
        }
      }
      await _db.from('driver_applications').insert({
        'user_id': user.id,
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'vehicle_category': _category,
        'vehicle_make_model': _vehicle.text.trim(),
        'vehicle_registration': _registration.text.trim().toUpperCase(),
      });
      _message = 'Application submitted. Go-Ride must review it before you can receive rides.';
      await _refresh();
    });
  }

  Future<void> _toggleAvailability(bool value) async {
    final areaId = _areaId;
    if (areaId == null) {
      _message = 'No active service area is configured.';
      setState(() {});
      return;
    }
    await _run(() async {
      await _db.rpc('driver_set_availability', params: {
        'p_area_id': areaId,
        'p_available': value,
      });
      _message = value ? 'You are now available in this service area.' : 'You are now offline.';
      await _refresh();
    });
  }

  Future<void> _requestSubscription(Map<String, dynamic> plan) async {
    await _run(() async {
      final user = _db.auth.currentUser;
      if (user == null) throw StateError('Please sign in.');
      final key = DateTime.now().microsecondsSinceEpoch.toString() + '-' + user.id;
      await _db.rpc('driver_request_subscription', params: {
        'p_plan_id': plan['id'],
        'p_idempotency_key': key,
      });
      _message = 'Subscription request created. It will remain pending until payment is verified and activated.';
      await _refresh();
    });
  }

  Future<void> _advanceRide(Map<String, dynamic> ride) async {
    final current = ride['status']?.toString() ?? '';
    final next = switch (current) {
      'driver_assigned' => 'driver_arriving',
      'driver_arriving' => 'driver_arrived',
      'driver_arrived' => 'in_trip',
      'in_trip' => 'completed',
      _ => '',
    };
    if (next.isEmpty) return;
    await _run(() async {
      await _db.rpc('driver_update_ride_status', params: {
        'p_ride_id': ride['id'],
        'p_new_status': next,
      });
      _message = 'Ride status updated to ' + next + '.';
      await _refresh();
    });
  }

  String _money(Map<String, dynamic> row, String key) =>
      _value(row, 'currency', 'INR') + ' ' + (((row[key] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2);

  String _value(Map<String, dynamic> row, String key, [String fallback = '—']) {
    final value = row[key];
    return value == null || value.toString().isEmpty ? fallback : value.toString();
  }

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _name.dispose();
    _vehicle.dispose();
    _registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isDriver) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Go-Ride Driver Partner'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : () => _run(_refresh),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: _busy ? null : () async {
                await _db.auth.signOut();
                if (mounted) setState(() {
                  _isDriver = false;
                  _isAvailable = false;
                  _message = 'Signed out.';
                });
              },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Driver dashboard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Availability is checked by the backend. Subscription areas require an active, unexpired subscription before you can go online.'),
              const SizedBox(height: 16),
              if (_areas.isEmpty)
                const Card(child: ListTile(title: Text('No active service areas'), subtitle: Text('Contact Go-Ride support; the Admin must configure an active area.')))
              else ...[
                DropdownButtonFormField<String>(
                  value: _areaId,
                  decoration: const InputDecoration(labelText: 'Service area'),
                  items: _areas.map((area) => DropdownMenuItem(
                    value: area['id'].toString(),
                    child: Text(_value(area, 'name') + ' · ' + _value(area, 'code')),
                  )).toList(),
                  onChanged: _busy ? null : (value) async {
                    if (value == null) return;
                    setState(() => _areaId = value);
                    await _run(_refresh);
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    value: _isAvailable,
                    onChanged: _busy ? null : _toggleAvailability,
                    title: Text(_isAvailable ? 'You are online' : 'You are offline'),
                    subtitle: Text('Business model: ' + _businessModel),
                    secondary: Icon(_isAvailable ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  ),
                ),
              ],
              if (_message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_message)),
              if (_busy) const LinearProgressIndicator(),
              if (_businessModel == 'subscription') ...[
                const SizedBox(height: 18),
                const Text('Subscription plans', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Requests remain pending until the Admin verifies payment. Do not treat a pending request as an active subscription.'),
                for (final plan in _plans)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.card_membership),
                      title: Text(_value(plan, 'name')),
                      subtitle: Text(_money(plan, 'price_minor') + ' · ' + (((plan['duration_minutes'] as num?)?.toInt() ?? 1440) / 60).toStringAsFixed(1) + ' hours'),
                      trailing: TextButton(
                        onPressed: _busy ? null : () => _requestSubscription(plan),
                        child: const Text('Request'),
                      ),
                    ),
                  ),
                if (_plans.isEmpty) const ListTile(title: Text('No active subscription plans for this area.')),
              ],
              const SizedBox(height: 18),
              const Text('Your subscriptions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              for (final subscription in _subscriptions)
                Card(
                  child: ListTile(
                    leading: Icon(subscription['status'] == 'active' ? Icons.check_circle_outline : Icons.schedule),
                    title: Text(_value(subscription, 'status').toUpperCase() + ' · ' + _money(subscription, 'price_minor_snapshot')),
                    subtitle: Text('Expires: ' + _value(subscription, 'expires_at', 'Not activated')),
                  ),
                ),
              const SizedBox(height: 18),
              const Text('Assigned rides', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              for (final ride in _rides)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_taxi),
                    title: Text(_value(ride, 'category') + ' · ' + _value(ride, 'status')),
                    subtitle: Text(_value(ride, 'pickup_label') + ' → ' + _value(ride, 'destination_label') + '\n' + _money(ride, 'fare_minor')),
                    isThreeLine: true,
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _advanceRide(ride),
                      child: Text(switch (ride['status']) {
                        'driver_assigned' => 'On my way',
                        'driver_arriving' => 'Arrived',
                        'driver_arrived' => 'Start trip',
                        'in_trip' => 'Complete',
                        _ => 'Update',
                      }),
                    ),
                  ),
                ),
              if (_rides.isEmpty) const ListTile(title: Text('No active rides assigned to you.')),
              const SizedBox(height: 16),
              const Text('Live GPS tracking, pickup OTP verification and driver earnings settlement are still pending before public launch.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Go-Ride Driver Partner'),
        actions: [
          if (_signedIn)
            IconButton(
              tooltip: 'Sign out',
              onPressed: _busy ? null : () async {
                await _db.auth.signOut();
                if (mounted) setState(() {
                  _application = null;
                  _message = 'Signed out.';
                });
              },
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Drive with Go-Ride', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Apply to become a partner. Approval is required before availability or ride dispatch can be enabled.'),
          const SizedBox(height: 20),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number with country code', hintText: '+91XXXXXXXXXX')),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : _sendOtp, child: const Text('Send SMS OTP')),
          const SizedBox(height: 10),
          TextField(controller: _otp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'SMS verification code')),
          OutlinedButton(onPressed: _busy ? null : _verifyOtp, child: const Text('Verify phone')),
          if (_signedIn && _application != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(_application!['status'] == 'approved' ? Icons.verified : _application!['status'] == 'rejected' ? Icons.cancel_outlined : Icons.pending_outlined),
                title: Text('Application status: ' + _value(_application!, 'status')),
                subtitle: Text(_value(_application!, 'review_note', 'Go-Ride will review your application.')),
              ),
            ),
          ],
          const Divider(height: 32),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Vehicle category'),
            items: const [
              DropdownMenuItem(value: 'BIKE', child: Text('Two-wheeler')),
              DropdownMenuItem(value: 'AUTO', child: Text('Auto rickshaw')),
              DropdownMenuItem(value: 'MINI', child: Text('Mini car')),
              DropdownMenuItem(value: 'SEDAN', child: Text('Sedan')),
            ],
            onChanged: _busy ? null : (value) { if (value != null) setState(() => _category = value); },
          ),
          const SizedBox(height: 10),
          TextField(controller: _vehicle, decoration: const InputDecoration(labelText: 'Vehicle make and model')),
          const SizedBox(height: 10),
          TextField(controller: _registration, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Vehicle registration number')),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || !_signedIn ? null : _submitApplication,
            icon: const Icon(Icons.assignment_turned_in_outlined),
            label: const Text('Submit driver application'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message)),
          const SizedBox(height: 12),
          const Text('Document uploads, live GPS tracking, pickup OTP verification and payment settlement still need completion before public launch.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
