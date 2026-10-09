import 'package:flutter/material.dart';

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
