import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const DriverPartnerApp());

class DriverPartnerApp extends StatelessWidget {
  const DriverPartnerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Go-Ride Driver Partner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B6B46)),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF55D6A0),
            brightness: Brightness.dark,
          ),
        ),
        home: const DriverHomePage(),
      );
}

class DriverHomePage extends StatelessWidget {
  const DriverHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Go-Ride Partner')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: const [
            _StatusCard(),
            SizedBox(height: 12),
            _BackendReadinessCard(),
            SizedBox(height: 20),
            Text('Your work', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            _UnavailableFeature(
              title: 'Go online',
              description: 'Online availability will be enabled after driver authentication, verification and dispatch are connected.',
              icon: Icons.power_settings_new,
            ),
            _UnavailableFeature(
              title: 'Ride offers',
              description: 'Ride offers are unavailable until the live dispatch service is configured.',
              icon: Icons.local_taxi_outlined,
            ),
            _UnavailableFeature(
              title: 'Earnings and trips',
              description: 'Earnings and trip history will appear after server-backed trip and payment records are available.',
              icon: Icons.account_balance_wallet_outlined,
            ),
            _UnavailableFeature(
              title: 'Support and safety',
              description: 'Support and emergency actions must be connected to real operational escalation before activation.',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Setup in progress', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    const Text('This app shell does not yet authenticate drivers or receive real ride requests. No fake online status or earnings are shown.'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _UnavailableFeature extends StatelessWidget {
  const _UnavailableFeature({required this.title, required this.description, required this.icon});
  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(description),
          trailing: const Chip(label: Text('Unavailable')),
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
  String _message = _baseUrl.isEmpty
      ? 'API URL not configured. Set GO_RIDE_API_BASE_URL at build time.'
      : 'Not checked yet.';
  bool? _ready;

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
            : 'Backend is not ready (HTTP ${response.statusCode}). Live actions remain unavailable.';
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
            const Text('Readiness is not proof that sign-in, dispatch or ride flows are operational.'),
          ]),
        ),
      );
}
