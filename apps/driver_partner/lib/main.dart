import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const DriverPartnerApp());
}

class DriverPartnerApp extends StatelessWidget {
  const DriverPartnerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Go-Ride Driver Partner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B46))),
        home: supabaseUrl.isEmpty || supabaseAnonKey.isEmpty
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
            child: Text('Go-Ride Driver Partner\n\nConfigure SUPABASE_URL and SUPABASE_ANON_KEY at build time. Never put a service-role key in this app.', textAlign: TextAlign.center),
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
  bool _busy = false;
  String _message = '';

  SupabaseClient get _db => Supabase.instance.client;
  bool get _signedIn => _db.auth.currentUser != null;

  Future<void> _sendOtp() async {
    await _run(() async {
      await _db.auth.signInWithOtp(phone: _phone.text.trim());
      _message = 'OTP requested. Enter the code sent to your phone.';
    });
  }

  Future<void> _verifyOtp() async {
    await _run(() async {
      await _db.auth.verifyOTP(phone: _phone.text.trim(), token: _otp.text.trim(), type: OtpType.sms);
      _message = 'Signed in. Complete your driver application below.';
    });
  }

  Future<void> _submitApplication() async {
    await _run(() async {
      final user = _db.auth.currentUser;
      if (user == null) throw StateError('Please verify your phone first.');
      await _db.from('driver_applications').insert({
        'user_id': user.id,
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'vehicle_category': _category,
        'vehicle_make_model': _vehicle.text.trim(),
        'vehicle_registration': _registration.text.trim().toUpperCase(),
      });
      _message = 'Application submitted. Go-Ride must review it before you can receive rides.';
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _message = ''; });
    try {
      await action();
    } catch (error) {
      _message = 'Could not complete this action. Check the details and Supabase Auth/SMS configuration.';
      debugPrint('Driver app action failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose(); _otp.dispose(); _name.dispose(); _vehicle.dispose(); _registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Go-Ride Driver Partner'), actions: [
          if (_signedIn) IconButton(tooltip: 'Sign out', onPressed: _busy ? null : () async { await _db.auth.signOut(); if (mounted) setState(() => _message = 'Signed out.'); }, icon: const Icon(Icons.logout)),
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
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
          const Divider(height: 32),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'Vehicle category'), items: const [
            DropdownMenuItem(value: 'BIKE', child: Text('Two-wheeler')),
            DropdownMenuItem(value: 'AUTO', child: Text('Auto rickshaw')),
            DropdownMenuItem(value: 'MINI', child: Text('Mini car')),
            DropdownMenuItem(value: 'SEDAN', child: Text('Sedan')),
          ], onChanged: _busy ? null : (value) { if (value != null) setState(() => _category = value); }),
          const SizedBox(height: 10),
          TextField(controller: _vehicle, decoration: const InputDecoration(labelText: 'Vehicle make and model')),
          const SizedBox(height: 10),
          TextField(controller: _registration, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Vehicle registration number')),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _busy || !_signedIn ? null : _submitApplication, icon: const Icon(Icons.assignment_turned_in_outlined), label: const Text('Submit driver application')),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          if (_message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_message)),
          const SizedBox(height: 12),
          const Text('This starter does not yet include document uploads, live location, online/offline status, ride offers or earnings.', style: TextStyle(color: Colors.grey)),
        ]),
      );
}
