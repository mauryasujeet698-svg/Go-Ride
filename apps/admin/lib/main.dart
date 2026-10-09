import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const GoRideAdminApp());

class GoRideAdminApp extends StatelessWidget {
  const GoRideAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Go-Ride Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF163A5F)),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8DBDFF),
            brightness: Brightness.dark,
          ),
        ),
        home: const AdminHomePage(),
      );
}

class AdminHomePage extends StatelessWidget {
  const AdminHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Go-Ride Admin')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Operations console setup', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    SizedBox(height: 8),
                    Text('Admin data and controls remain unavailable until secure authentication, server authorization and audit logging are connected.'),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            const _BackendReadinessCard(),
            SizedBox(height: 20),
            _AdminModule(title: 'Driver verification', description: 'Review and approve driver documents through audited server actions.', icon: Icons.verified_user_outlined),
            _AdminModule(title: 'Ride monitoring', description: 'View authoritative ride status and event history when the backend is configured.', icon: Icons.route_outlined),
            _AdminModule(title: 'Support and safety cases', description: 'Manage cases with role-based access, ownership and escalation.', icon: Icons.support_agent_outlined),
            _AdminModule(title: 'Payments and reconciliation', description: 'Payment operations are disabled until a provider and server-side reconciliation are configured.', icon: Icons.payments_outlined),
            _AdminModule(title: 'Feature availability', description: 'Feature flags require authenticated, audited backend controls; no local-only switch can enable production features.', icon: Icons.toggle_on_outlined),
            _AdminModule(title: 'Audit and reports', description: 'Reports must use server data and respect least-privilege access.', icon: Icons.fact_check_outlined),
          ],
        ),
      );
}

class _AdminModule extends StatelessWidget {
  const _AdminModule({required this.title, required this.description, required this.icon});
  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(description),
          trailing: const Chip(label: Text('Not connected')),
        ),
      );
}

class _BackendReadinessCard extends StatefulWidget {
  const _BackendReadinessCard();

  @override
  State<_BackendReadinessCard> createState() => _BackendReadinessCardState();
}

class _BackendReadinessCardState extends State<_BackendReadinessCard> {
  static const _baseUrl = String.fromEnvironment('GO_RIDE_API_BASE_URL');
  bool _checking = false;
  bool? _ready;
  String _message = _baseUrl.isEmpty
      ? 'API URL not configured. Set GO_RIDE_API_BASE_URL at build time.'
      : 'Backend readiness has not been checked.';

  Future<void> _check() async {
    if (_baseUrl.isEmpty) {
      setState(() { _ready = false; _message = 'API URL is not configured for this build.'; });
      return;
    }
    setState(() { _checking = true; _message = 'Checking backend readiness…'; });
    try {
      final base = Uri.parse(_baseUrl);
      if (!base.hasScheme || !base.hasAuthority || !['https', 'http'].contains(base.scheme)) {
        throw const FormatException('The configured API URL is invalid.');
      }
      final response = await http.get(base.resolve('/health/ready')).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _ready = response.statusCode == 200;
        _message = _ready == true
            ? 'Backend reports ready.'
            : 'Backend is not ready (HTTP ${response.statusCode}). Admin actions remain unavailable.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _ready = false; _message = 'Backend could not be reached. Check network and API configuration.'; });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_ready == true ? Icons.cloud_done : Icons.cloud_off_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text('Backend connection', style: Theme.of(context).textTheme.titleMedium)),
              IconButton(onPressed: _checking ? null : _check, tooltip: 'Check backend readiness', icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh)),
            ]),
            Text(_message),
            const SizedBox(height: 6),
            const Text('Readiness does not replace admin authentication, permissions or audit checks.'),
          ]),
        ),
      );
}
