import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/location_detail_screen.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('Handling a background message: ${message.messageId}');
}

Future<void> main() async {
  print('Starting app initialization...');
  WidgetsFlutterBinding.ensureInitialized();
  print('Widgets initialized...');

  print('Initializing Firebase...');
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    print('Firebase initialized!');
  } catch (e) {
    print('Firebase init failed: $e');
  }

  print('Initializing Supabase...');
  try {
    await Supabase.initialize(
      url: 'https://aiqqunfuiegfwrjmjpmb.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFpcXF1bmZ1aWVnZndyam1qcG1iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2NDMyMDMsImV4cCI6MjA4OTIxOTIwM30.oL_WsWL7xArwT3_mMQkrB4WS48gv2HisixFilqGLl-M',
    );
    print('Supabase initialized!');
  } catch (e) {
    print('Supabase init failed: $e');
  }

  runApp(const MyApp());
  print('runApp called!');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sports Community',
      theme: AppTheme.buildTheme(),
      home: const AuthGate(),
      builder: (context, child) {
        return Container(
          color: const Color(0xFFE5E7EB), // Beautiful subtle gray background for the sides
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480), // Perfect mobile proportion
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      onGenerateRoute: (settings) {
        if (settings.name != null && settings.name!.startsWith('/place/')) {
          final id = settings.name!.split('/')[2];
          return MaterialPageRoute(
            builder: (context) => LocationDetailScreen(placeId: id),
          );
        }
        return null;
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return Supabase.instance.client.auth.currentSession == null
        ? const LoginScreen()
        : const MainScreen();
  }
}
