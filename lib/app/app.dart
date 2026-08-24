import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/data/services/auth_service.dart';
import '../features/auth/presentation/pages/auth_gate.dart';
import '../features/calls/presentation/widgets/incoming_call_listener.dart';
import 'navigation/app_navigator.dart';
import 'navigation/auth_navigation_coordinator.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class VonoTalkyApp extends StatefulWidget {
  const VonoTalkyApp({super.key});

  @override
  State<VonoTalkyApp> createState() => _VonoTalkyAppState();
}

class _VonoTalkyAppState extends State<VonoTalkyApp> {
  late final AuthNavigationCoordinator _authNavigationCoordinator;

  @override
  void initState() {
    super.initState();

    _authNavigationCoordinator = AuthNavigationCoordinator(
      authStateChanges: AuthService().authStateChanges,
      navigatorKey: AppNavigator.key,
    )..start();
  }

  @override
  void dispose() {
    unawaited(_authNavigationCoordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<VonoThemePreferences>(
        valueListenable: VonoThemeController.instance,
        builder: (context, preferences, _) => MaterialApp(
          navigatorKey: AppNavigator.key,
          debugShowCheckedModeBanner: false,
          title: 'VonoTalky',
          themeMode: preferences.mode,
          theme: AppTheme.light(preferences.color),
          darkTheme: AppTheme.dark(preferences.color),
          home: const IncomingCallListener(child: AuthGate()),
          onGenerateRoute: AppRouter.onGenerateRoute,
        ),
      );
}
