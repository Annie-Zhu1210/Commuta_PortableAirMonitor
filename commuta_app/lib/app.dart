import 'package:flutter/material.dart';
import 'core/constants/app_colours.dart';
import 'screens/home/home_screen.dart';
import 'screens/map/map_screen.dart';
import 'screens/history/history_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'widgets/animated_bottom_nav_bar.dart';
import 'widgets/top_status_bar.dart';
import 'dart:async';
import 'services/app_services.dart';

class CommutaApp extends StatelessWidget {
  const CommutaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commuta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        scaffoldBackgroundColor: AppColours.background,
        colorScheme: ColorScheme.light(primary: AppColours.accent),
      ),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Start station auto-classification for the whole session. This is
    // the one place location permission is requested for now (until the
    // onboarding flow exists). Fire-and-forget: if permission is refused,
    // classification stays dormant and readings still persist unclassified.
    unawaited(
      AppServices.instance.classificationService.startLocationTracking(),
    );
  }

  final List<Widget> _screens = const [
    HomeScreen(),
    MapScreen(),
    HistoryScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      appBar: const TopStatusBar(
        connectionState: DeviceConnectionState.disconnected,
        batteryState: BatteryState.unknown,
      ),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: AnimatedBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColour: Colors.white,
        selectedItemColour: AppColours.accent,
        unselectedItemColour: AppColours.textSecondary,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.air_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
