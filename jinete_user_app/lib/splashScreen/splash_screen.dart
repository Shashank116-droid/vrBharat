import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete/authentication/login_screen.dart';
import 'package:jinete/methods/common_methods.dart';
import 'package:jinete/pages/dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _textColor = Colors.white;
  CommonMethods cMethods = CommonMethods();

  startTimer() {
    Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      // Check if user is already logged in
      if (FirebaseAuth.instance.currentUser != null) {
        Navigator.pushReplacement(context, cMethods.createRoute(Dashboard()));
      } else {
        Navigator.pushReplacement(context, cMethods.createRoute(LoginScreen()));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              "assets/images/logo.png",
              height: 150, // Larger visual for splash
            ),
            const SizedBox(height: 20),
            Text(
              "Student Ride-Sharing",
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
