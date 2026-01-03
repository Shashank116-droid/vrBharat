import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:jinete/pages/dashboard.dart';
import 'package:permission_handler/permission_handler.dart';

import 'splashScreen/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Handle error
  }

  try {
    await Permission.locationWhenInUse.isDenied.then((valueOfPermission) {
      if (valueOfPermission) {
        Permission.locationWhenInUse.request();
      }
    });
  } catch (e) {
    // Handle error
  }

  runApp(JineteApp());
}

class JineteApp extends StatelessWidget {
  const JineteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jinete - Campus Carpool',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: FirebaseAuth.instance.currentUser == null
          ? const SplashScreen()
          : const Dashboard(),
      debugShowCheckedModeBanner: false,
    );
  }
}
