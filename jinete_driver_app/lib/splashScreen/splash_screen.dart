import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_database/firebase_database.dart'; // Removed
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete_driver_app/authentication/login_screen.dart';
import 'package:jinete_driver_app/authentication/signup_screen.dart';
import 'package:jinete_driver_app/pages/dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _textColor = Colors.white;

  startTimer() {
    Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      // Check if user is already logged in
      if (FirebaseAuth.instance.currentUser != null) {
        FirebaseFirestore.instance
            .collection("drivers")
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .get()
            .then((docSnapshot) {
              if (FirebaseAuth.instance.currentUser == null) {
                return; // Handle edge case where user signs out mid-check
              }
              if (docSnapshot.exists) {
                if (docSnapshot.data()!["blockStatus"] == "no") {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (c) => const Dashboard()),
                  );
                } else {
                  FirebaseAuth.instance.signOut();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (c) => const LoginScreen()),
                  );
                }
              } else {
                // Logged in but no driver profile -> Profile Completion
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (c) => SignUpScreen(
                      existingUser: FirebaseAuth.instance.currentUser,
                    ),
                  ),
                );
              }
            });
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (c) => const LoginScreen()),
        );
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
