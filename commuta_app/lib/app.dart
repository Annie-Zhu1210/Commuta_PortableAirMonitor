import 'dart:async';

import 'package:flutter/material.dart';

import 'core/constants/app_colours.dart';
import 'screens/history/history_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/map/map_screen.dart';
import 'screens/profile/device/device_section_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/scan_pair/scan_pair_screen.dart';
import 'services/app_services.dart';
import 'services/device_connection.dart';
import 'widgets/adapter_state_banner.dart';
import 'widgets/animated_bottom_nav_bar.dart';
import 'widgets/top_status_bar.dart';

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

  // Cached interface reference — the underlying instance is a
  // process-wide singleton, so caching is safe and cheap.
  final DeviceConnection _connection =
      AppServices.instance.deviceConnection;

  @override
  void initState() {
    super.initState();
    // Start station auto-classification for the whole session. This
    // is the one place location permission is requested for now
    // (until the onboarding flow exists). Fire-and-forget: if
    // permission is refused, classification stays dormant and
    // readings still persist unclassified.
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

  /// Top-bar tap handler. Routes based on whether a device has ever
  /// been paired:
  ///   * unpaired → [ScanPairScreen] (start scan on entry)
  ///   * paired   → [DeviceSectionScreen] (status + reconnect/forget)
  ///
  /// The banner takes precedence visually, but the tap still fires
  /// regardless of adapter state — the destination screens show
  /// their own inline banner so the user always lands somewhere
  /// with clear next steps.
  void _handleStatusTap() {
    final isPaired = _connection.pairingCompleteListenable.value;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isPaired
            ? const DeviceSectionScreen()
            : const ScanPairScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      appBar: _StatusBarBinder(
        connection: _connection,
        onTap: _handleStatusTap,
      ),
      body: Column(
        children: [
          _AdapterBannerBinder(connection: _connection),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
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

// ─────────────────────────────────────────────────────────────────
// Binders — wrap the two live surfaces (status chip + adapter banner)
// so the scaffold itself stays clean and each surface rebuilds only
// on the streams it depends on.
// ─────────────────────────────────────────────────────────────────

/// Wraps [TopStatusBar] with the three data sources it depends on:
/// connection state, pair state, and the latest status packet.
/// Implements [PreferredSizeWidget] so it can slot straight into
/// [Scaffold.appBar].
class _StatusBarBinder extends StatelessWidget
    implements PreferredSizeWidget {
  const _StatusBarBinder({required this.connection, required this.onTap});

  final DeviceConnection connection;
  final VoidCallback onTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: connection.pairingCompleteListenable,
      builder: (context, isPaired, _) {
        return StreamBuilder<DeviceConnectionState>(
          stream: connection.stateStream,
          builder: (context, stateSnap) {
            return StreamBuilder<DeviceStatus>(
              stream: connection.statusStream,
              builder: (context, statusSnap) {
                return TopStatusBar(
                  connectionState:
                      stateSnap.data ?? DeviceConnectionState.idle,
                  isPaired: isPaired,
                  batteryPercent: statusSnap.data?.batteryPercent ??
                      connection.batteryPercent,
                  onTap: onTap,
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Wraps [AdapterStateBanner] with the adapter state stream so it
/// takes zero space when the adapter is on and renders inline when
/// it isn't.
class _AdapterBannerBinder extends StatelessWidget {
  const _AdapterBannerBinder({required this.connection});

  final DeviceConnection connection;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BluetoothAvailability>(
      stream: connection.adapterStateStream,
      builder: (context, snapshot) {
        return AdapterStateBanner(
          availability: snapshot.data ?? connection.adapterState,
        );
      },
    );
  }
}
