import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_dashboard.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const adminRedirectUri = 'io.supabase.gorideadmin://login-callback/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
  }
  runApp(const GoRideAdminApp());
}

class GoRideAdminApp extends StatelessWidget {
  const GoRideAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Go-Ride Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF163A5F)),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: supabaseUrl.isEmpty || supabasePublishableKey.isEmpty
            ? const _ConfigurationPage()
            : const _AdminGate(),
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
              'Go-Ride Admin\n\nConfigure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY at build time. Admin access must be granted separately by a trusted administrator. Never embed a service-role key.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

class _AdminGate extends StatefulWidget {
  const _AdminGate();

  @override
  State<_AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<_AdminGate> {
  bool _busy = false;
  bool _isAdmin = false;
  String _message = 'Sign in with the authorized Google account for Go-Ride Admin.';
  StreamSubscription<AuthState>? _authSubscription;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _authSubscription = _db.auth.onAuthStateChange.listen((state) {
      if (state.session != null) {
        _run(_checkRole);
      } else if (mounted) {
        setState(() {
          _isAdmin = false;
          _message = 'Sign in with the authorized Google account for Go-Ride Admin.';
        });
      }
    });
    if (_db.auth.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run(_checkRole));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (mounted) setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _message = 'Action failed. Verify Google OAuth settings and the Supabase role policy.';
      debugPrint('Admin app action failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() => _run(() async {
        await _db.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: adminRedirectUri,
        );
        _message = 'Continue in the browser to sign in with Google. You will return to Go-Ride Admin.';
      });

  Future<void> _checkRole() async {
    final user = _db.auth.currentUser;
    if (user == null) {
      _isAdmin = false;
      _message = 'Please sign in first.';
      return;
    }
    final roles = await _db
        .from('user_roles')
        .select('role,status,revoked_at')
        .eq('user_id', user.id)
        .eq('role', 'admin')
        .eq('status', 'active')
        .isFilter('revoked_at', null);
    _isAdmin = (roles as List).isNotEmpty;
    _message = _isAdmin
        ? 'Admin role verified.'
        : 'Access denied. This Google account has no active admin role; no admin privileges were granted.';
  }

  Future<void> _signOut() async {
    await _db.auth.signOut();
    if (!mounted) return;
    setState(() {
      _isAdmin = false;
      _message = 'Signed out.';
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAdmin) return AdminDashboard(onSignOut: _signOut);

    return Scaffold(
      appBar: AppBar(title: const Text('Go-Ride Admin')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Operations console', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Sign in with Google. Admin access is deny-by-default and requires an explicit server-managed role; signing in alone never grants administrative privileges.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _signInWithGoogle,
            icon: const Icon(Icons.login),
            label: const Text('Continue with Google'),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(_isAdmin ? Icons.verified_user : Icons.lock_outline),
              title: Text(_isAdmin ? 'Admin role active' : 'Admin access restricted'),
              subtitle: Text(_message),
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_db.auth.currentUser != null)
            OutlinedButton.icon(
              onPressed: _busy ? null : _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          const SizedBox(height: 12),
          const Text(
            'Never put a Supabase service-role key in this app. Sensitive operations use server-side database functions.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
