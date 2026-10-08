import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00B84F),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 172,
                  height: 172,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: SvgPicture.asset(
                    'assets/goride_logo.svg',
                    semanticsLabel: 'Go-Ride logo',
                  ),
                ),
                const SizedBox(height: 28),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                    children: [
                      TextSpan(
                        text: 'Go-',
                        style: TextStyle(color: Color(0xFF102235)),
                      ),
                      TextSpan(
                        text: 'Ride',
                        style: TextStyle(color: Color(0xFF00B84F)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'RIDE  •  RELIABLE  •  NEAR YOU',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF52606D),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 58),
                const Text(
                  'Go-Ride foundation build',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF102235),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Domain and synchronization layers are ready. '
                  'Infrastructure and live ride UI are added in the next application phase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
