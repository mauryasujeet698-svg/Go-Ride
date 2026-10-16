import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const GoRideAdminApp());
}

class GoRideAdminApp extends StatelessWidget {
  const GoRideAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Go-Ride Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF163A5F))),
        home: supabaseUrl.isEmpty || supabaseAnonKey.isEmpty
            ? const _ConfigurationPage()
            : const _AdminGate(),
      );
}

class _ConfigurationPage extends StatelessWidget {
  const _ConfigurationPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Go-Ride Admin\n\nConfigure SUPABASE_URL and SUPABASE_ANON_KEY at build time. Admin access must be granted separately by a trusted administrator. Never embed a service-role key.', textAlign: TextAlign.center),
        )),
      );
}

class _AdminGate extends StatefulWidget {
  const _AdminGate();

  @override
  State<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<_AdminGate> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _busy = false;
  bool _isAdmin = false;
  String _message = 'Sign in with an authorized admin account.';

  SupabaseClient get _db => Supabase.instance.client;

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; });
    try {
      await action();
    } catch (error) {
      _message = 'Action failed. Verify phone/SMS settings and the Supabase role policy.';
      debugPrint('Admin app action failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOtp() => _run(() async {
    await _db.auth.signInWithOtp(phone: _phone.text.trim());
    _message = 'OTP requested. Enter the code sent to your phone.';
  });

  Future<void> _verifyOtp() => _run(() async {
    await _db.auth.verifyOTP(phone: _phone.text.trim(), token: _otp.text.trim(), type: OtpType.sms);
    await _checkRole();
  });

  Future<void> _checkRole() async {
    final user = _db.auth.currentUser;
    if (user == null) { _isAdmin = false; _message = 'Please sign in first.'; return; }
    final roles = await _db.from('user_roles').select('role,status').eq('user_id', user.id).eq('role', 'admin').eq('status', 'active');
    _isAdmin = (roles as List).isNotEmpty;
    _message = _isAdmin
        ? 'Admin role verified. Operational actions still require audited server endpoints.'
        : 'Access denied. This account has no active admin role; no admin privileges were granted.';
  }

  @override
  void dispose() { _phone.dispose(); _otp.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Go-Ride Admin'), actions: [
          if (_db.auth.currentUser != null) IconButton(tooltip: 'Sign out', onPressed: _busy ? null : () async { await _db.auth.signOut(); if (mounted) setState(() { _isAdmin = false; _message = 'Signed out.'; }); }, icon: const Icon(Icons.logout)),
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Operations console', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Admin access is deny-by-default. The app checks an explicit server-managed role; a normal account cannot promote itself.'),
          const SizedBox(height: 20),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Admin phone number with country code')),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : _sendOtp, child: const Text('Send SMS OTP')),
          const SizedBox(height: 10),
          TextField(controller: _otp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'SMS verification code')),
          OutlinedButton(onPressed: _busy ? null : _verifyOtp, child: const Text('Verify and check admin role')),
          const SizedBox(height: 16),
          Card(child: ListTile(
            leading: Icon(_isAdmin ? Icons.verified_user : Icons.lock_outline),
            title: Text(_isAdmin ? 'Admin role active' : 'Admin access restricted'),
            subtitle: Text(_message),
          )),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: 12),
          const Text('Driver review queues, ride controls, payments, support actions and reports are not exposed until audited server-side admin endpoints are implemented.', style: TextStyle(color: Colors.grey)),
        ]),
      );
}
