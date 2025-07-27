// File: lib/main.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:local_auth/local_auth.dart';

import 'firebase_options.dart';
import 'signing/login.dart';
import 'mainpage.dart';
import 'utlis/colors.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prevent duplicate initialization:
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  runApp(
    MaterialApp(
      navigatorKey: navKey,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      theme: blueTheme,
    ),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _AuthGateState createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _localAuth = LocalAuthentication();
  bool _didCheckBiometric = false;
  // ignore: unused_field
  bool _biometricPassed = false;

  @override
  void initState() {
    super.initState();
    _tryAuthenticate();
  }

  Future<void> _tryAuthenticate() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // not signed in, skip biometrics
      setState(() => _didCheckBiometric = true);
      return;
    }

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final available = await _localAuth.getAvailableBiometrics();

      if (canCheck && available.isNotEmpty) {
        final didAuth = await _localAuth.authenticate(
          localizedReason: 'Please authenticate to unlock your Finity vault',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
          ),
        );
        if (didAuth) {
          _biometricPassed = true;
          _didCheckBiometric = true;
          setState(() {});
          return;
        }
      } else {
        // no biometrics available
        _biometricPassed = true;
        _didCheckBiometric = true;
        setState(() {});
        return;
      }
    } catch (e) {
      // platform or activity issues → skip biometrics
      _biometricPassed = true;
      _didCheckBiometric = true;
      setState(() {});
      return;
    }

    // biometric failed → sign out
    await FirebaseAuth.instance.signOut();
    setState(() => _didCheckBiometric = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_didCheckBiometric) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginPage();
    }

    // user is signed in and biometrics (if any) passed
    return const MainPage();
  }
}
