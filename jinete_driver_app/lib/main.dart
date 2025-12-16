import 'package:flutter/material.dart';
import 'package:jinete_driver_app/firebase_options.dart';
import 'package:jinete_driver_app/splashScreen/splash_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Permission.locationWhenInUse.isDenied.then((valueOfPermission) {
    if (valueOfPermission) {
      Permission.locationWhenInUse.request();
    }
  });

  runApp(JineteApp());
}

class JineteApp extends StatelessWidget {
  const JineteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jinete - Campus Carpool',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
