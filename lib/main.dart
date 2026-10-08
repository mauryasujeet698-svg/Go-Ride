import 'package:flutter/material.dart';

void main() {
  runApp(const GoRideApp());
}

class GoRideApp extends StatelessWidget {
  const GoRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Go-Ride',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const GoRideFoundationPage(),
    );
  }
}

class GoRideFoundationPage extends StatelessWidget {
  const GoRideFoundationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Go-Ride')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Go-Ride foundation build\n\n'
            'Domain and synchronization layers are ready. '
            'Infrastructure and live ride UI are added in the next application phase.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
