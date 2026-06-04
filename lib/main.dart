import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'viewmodels/auth_viewmodel.dart';
import 'views/auth/login_view.dart';
import 'views/dashboard/dashboard_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://wsmwxtcdjvburvptuqbb.supabase.co',         // ← replace with your project URL
    publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndzbXd4dGNkanZidXJ2cHR1cWJiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1NzY5ODAsImV4cCI6MjA5NjE1Mjk4MH0.ayAuRfGzLl6AwPeSQsJL9KpWEv6sKH9e_3tL85Yyrvs', // ← replace with your anon key
  );

  runApp(const SmartMatchApp());
}

class SmartMatchApp extends StatelessWidget {
  const SmartMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthViewModel(),
      child: MaterialApp(
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
        },
      ),
    );
  }
}
