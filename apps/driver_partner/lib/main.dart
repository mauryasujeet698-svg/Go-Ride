import 'package:flutter/material.dart';

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
