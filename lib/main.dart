import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  runApp(const GoRideApp());
}

class GoRideApp extends StatelessWidget {
  const GoRideApp({super.key});

  static const _navy = Color(0xFF102235);
  static const _green = Color(0xFF00B84F);
  static const _background = Color(0xFFF7F9FC);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Go-Ride',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: _background,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: _background,
          foregroundColor: _navy,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE4EAF0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _green, width: 1.5),
          ),
        ),
      ),
      home: const GoRideShell(),
    );
  }
}

class GoRideShell extends StatefulWidget {
  const GoRideShell({super.key});

  @override
  State<GoRideShell> createState() => _GoRideShellState();
}

class _GoRideShellState extends State<GoRideShell> {
  int _selectedIndex = 0;
  final _booking = _BookingDraft();

  @override
  Widget build(BuildContext context) {
    final pages = [
      GoRideHomePage(
        booking: _booking,
        onBook: _openReview,
      ),
      const _TripsPage(),
      const _ProfilePage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Future<void> _openReview() async {
    FocusManager.instance.primaryFocus?.unfocus();

    if (!_booking.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both pickup and destination.'),
        ),
      );
      return;
    }

    if (_booking.active) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _RideRequestStatusPage(booking: _booking),
        ),
      );
      if (mounted) setState(() {});
      return;
    }

    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _RideReviewPage(booking: _booking),
      ),
    );

    if (submitted == true && mounted) {
      setState(() {});
    }
  }
}

class GoRideHomePage extends StatefulWidget {
  const GoRideHomePage({
    required this.booking,
    required this.onBook,
    super.key,
  });

  final _BookingDraft booking;
  final VoidCallback onBook;

  @override
  State<GoRideHomePage> createState() => _GoRideHomePageState();
}

class _GoRideHomePageState extends State<GoRideHomePage> {
  final _pickupController = TextEditingController();
  final _destinationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pickupController.text = widget.booking.pickup;
    _destinationController.text = widget.booking.destination;
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _syncBooking() {
    widget.booking
      ..pickup = _pickupController.text.trim()
      ..destination = _destinationController.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: GoRideApp._background,
            titleSpacing: 20,
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: SvgPicture.asset('assets/goride_logo.svg'),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Go-Ride',
                  style: TextStyle(
                    color: GoRideApp._navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Notifications will be connected to the backend.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const Text(
                  'Where are you going?',
                  style: TextStyle(
                    color: GoRideApp._navy,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Book a ride in a few simple steps.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 22),
                _LocationCard(
                  pickupController: _pickupController,
                  destinationController: _destinationController,
                  onChanged: () {
                    setState(_syncBooking);
                  },
                  onSwap: () {
                    final oldPickup = _pickupController.text;
                    _pickupController.text = _destinationController.text;
                    _destinationController.text = oldPickup;
                    setState(_syncBooking);
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'Choose your ride',
                  style: TextStyle(
                    color: GoRideApp._navy,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                ...RideType.values.map(
                  (type) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RideOptionCard(
                      type: type,
                      selected: booking.type == type,
                      onTap: () {
                        setState(() {
                          booking.type = type;
                          _syncBooking();
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () {
                    _syncBooking();
                    widget.onBook();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: GoRideApp._green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text(
                    booking.active ? 'View current ride' : 'Continue',
                  ),
                ),
                const SizedBox(height: 18),
                const _SecurityBanner(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.pickupController,
    required this.destinationController,
    required this.onChanged,
    required this.onSwap,
  });

  final TextEditingController pickupController;
  final TextEditingController destinationController;
  final VoidCallback onChanged;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFE4EAF0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: pickupController,
              onChanged: (_) => onChanged(),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Pickup location',
                prefixIcon: Icon(
                  Icons.radio_button_checked,
                  color: GoRideApp._green,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Swap locations',
                onPressed: onSwap,
                icon: const Icon(Icons.swap_vert_rounded),
              ),
            ),
            TextField(
              controller: destinationController,
              onChanged: (_) => onChanged(),
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Destination',
                prefixIcon: Icon(
                  Icons.location_on_outlined,
                  color: GoRideApp._navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideOptionCard extends StatelessWidget {
  const _RideOptionCard({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final RideType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFEAF9F0) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? GoRideApp._green
                  : const Color(0xFFE4EAF0),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: selected
                    ? GoRideApp._green
                    : const Color(0xFFF1F4F7),
                foregroundColor: selected
                    ? Colors.white
                    : GoRideApp._navy,
                child: Icon(type.icon),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: const TextStyle(
                        color: GoRideApp._navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      type.subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? GoRideApp._green
                    : const Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: GoRideApp._navy),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ride state is designed to be authoritative on the secure server. '
              'Live matching and payment are connected in the backend phase.',
              style: TextStyle(
                color: GoRideApp._navy,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RideReviewPage extends StatelessWidget {
  const _RideReviewPage({required this.booking});

  final _BookingDraft booking;

  @override
  Widget build(BuildContext context) {
    final estimate = booking.estimatedFare;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Review ride',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SummaryCard(
            pickup: booking.pickup,
            destination: booking.destination,
            type: booking.type,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estimated fare',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '₹' + estimate.toString(),
                  style: const TextStyle(
                    color: GoRideApp._navy,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Final fare comes from the server after route and ride assignment are available.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () {
              booking.active = true;
              booking.lastRideId =
                  'GR-' + DateTime.now().millisecondsSinceEpoch.toString();
              Navigator.of(context).pop(true);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      _RideRequestStatusPage(booking: booking),
                ),
              );
            },
            icon: const Icon(Icons.local_taxi_outlined),
            label: const Text('Request ride'),
            style: FilledButton.styleFrom(
              backgroundColor: GoRideApp._green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.pickup,
    required this.destination,
    required this.type,
  });

  final String pickup;
  final String destination;
  final RideType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: GoRideApp._navy,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          _RouteRow(
            icon: Icons.radio_button_checked,
            label: 'Pickup',
            value: pickup,
            iconColor: GoRideApp._green,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Divider(color: Color(0xFF304156), height: 22),
          ),
          _RouteRow(
            icon: Icons.location_on,
            label: 'Destination',
            value: destination,
            iconColor: Colors.white,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(type.icon, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                type.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFB9C5D1),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RideRequestStatusPage extends StatelessWidget {
  const _RideRequestStatusPage({required this.booking});

  final _BookingDraft booking;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Current ride',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: Color(0xFFEAF9F0),
                  foregroundColor: GoRideApp._green,
                  child: Icon(Icons.schedule_rounded, size: 36),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Ride request created',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: GoRideApp._navy,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  booking.lastRideId ?? '',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'The customer flow is working. Live driver matching is intentionally not simulated; the next backend phase will connect this request to the authoritative ride service.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF667085),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton(
            onPressed: () {
              booking.active = false;
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
              ),
            ),
            child: const Text(
              'Close request',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripsPage extends StatelessWidget {
  const _TripsPage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        children: [
          const Text(
            'Your trips',
            style: TextStyle(
              color: GoRideApp._navy,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Completed and active rides will appear here.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  color: GoRideApp._navy,
                  size: 44,
                ),
                SizedBox(height: 14),
                Text(
                  'No trips yet',
                  style: TextStyle(
                    color: GoRideApp._navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        children: [
          const Text(
            'Profile',
            style: TextStyle(
              color: GoRideApp._navy,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE4EAF0)),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFFEAF9F0),
                  foregroundColor: GoRideApp._green,
                  child: Icon(Icons.person, size: 30),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guest rider',
                        style: TextStyle(
                          color: GoRideApp._navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Secure account connection comes in the backend phase.',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ProfileTile(
            icon: Icons.location_on_outlined,
            title: 'Saved places',
          ),
          _ProfileTile(
            icon: Icons.shield_outlined,
            title: 'Security',
          ),
          _ProfileTile(
            icon: Icons.help_outline,
            title: 'Help & support',
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: GoRideApp._navy),
        title: Text(
          title,
          style: const TextStyle(
            color: GoRideApp._navy,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(title + ' will be connected next.')),
          );
        },
      ),
    );
  }
}

enum RideType {
  bike,
  auto,
  cab;

  String get label {
    switch (this) {
      case RideType.bike:
        return 'Go-Bike';
      case RideType.auto:
        return 'Go-Auto';
      case RideType.cab:
        return 'Go-Cab';
    }
  }

  String get subtitle {
    switch (this) {
      case RideType.bike:
        return 'Fast and economical';
      case RideType.auto:
        return 'Comfortable everyday ride';
      case RideType.cab:
        return 'More space, more comfort';
    }
  }

  IconData get icon {
    switch (this) {
      case RideType.bike:
        return Icons.two_wheeler;
      case RideType.auto:
        return Icons.electric_rickshaw_outlined;
      case RideType.cab:
        return Icons.local_taxi_outlined;
    }
  }
}

class _BookingDraft {
  String pickup = '';
  String destination = '';
  RideType type = RideType.auto;
  bool active = false;
  String? lastRideId;

  bool get isValid => pickup.isNotEmpty && destination.isNotEmpty;

  int get estimatedFare {
    switch (type) {
      case RideType.bike:
        return 69 + math.max(0, pickup.length + destination.length - 20);
      case RideType.auto:
        return 99 + math.max(0, pickup.length + destination.length - 15);
      case RideType.cab:
        return 149 + math.max(0, pickup.length + destination.length - 10);
    }
  }
}
