import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'viewmodels/auth_viewmodel.dart';
import 'views/auth/login_view.dart';
import 'views/auth/update_password_view.dart';
import 'views/dashboard/dashboard_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://wsmwxtcdjvburvptuqbb.supabase.co',
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndzbXd4dGNkanZidXJ2cHR1cWJiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1NzY5ODAsImV4cCI6MjA5NjE1Mjk4MH0.ayAuRfGzLl6AwPeSQsJL9KpWEv6sKH9e_3tL85Yyrvs',
  );

  // Provide AuthViewModel above the entire app so it is never recreated
  // or torn down during navigation/rebuilds.
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthViewModel(),
      child: const SmartMatchApp(),
    ),
  );
}

class SmartMatchApp extends StatefulWidget {
  const SmartMatchApp({super.key});

  @override
  State<SmartMatchApp> createState() => _SmartMatchAppState();
}

class _SmartMatchAppState extends State<SmartMatchApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    // Listen for Supabase auth events (e.g. password recovery deep link)
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/update-password', (_) => false);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'TAR UMT SmartMatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const LoginView(),
      routes: {
        '/login': (_) => const LoginView(),
        '/dashboard': (_) => const DashboardView(),
        '/update-password': (_) => const UpdatePasswordView(),
      },
    );
  }
}
