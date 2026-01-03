import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete/authentication/signup_screen.dart';
import 'package:jinete/authentication/otp_verification_screen.dart'; // Added

import '../methods/common_methods.dart';
import '../widgets/loading_dialog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  TextEditingController phoneTextEditingController = TextEditingController();
  CommonMethods cMethods = CommonMethods();

  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor =
      const Color(0xFF181820); // Slightly lighter than background
  final Color _inputColor = const Color(0xFF252530); // Input field background
  final Color _accentColor = const Color(0xFFFF6B00); // Orange
  final Color _textColor = Colors.white;
  final Color _hintColor = Colors.white54;

  void validatePhone() {
    if (phoneTextEditingController.text.trim().length < 10) {
      cMethods.displaySnackBar("Please enter valid phone number", context,
          isError: true);
      return;
    }
    verifyPhoneNumber();
  }

  void verifyPhoneNumber() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Sending OTP..."),
    );

    String phoneNumber = phoneTextEditingController.text.trim();
    if (!phoneNumber.startsWith("+")) {
      phoneNumber = "+91$phoneNumber";
    }

    // Check if user exists in Firestore
    try {
      final QuerySnapshot userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .get();

      if (userQuery.docs.isEmpty) {
        if (!context.mounted) return;
        Navigator.pop(context); // Close loading dialog
        cMethods.displaySnackBar(
            "Your User Account does not exist, Please Sign Up before Logging In again",
            context,
            isError: true);
        return;
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      cMethods.displaySnackBar("Error checking user: ${e.toString()}", context,
          isError: true);
      return;
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-verification (rare)
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        Navigator.pop(context);
        cMethods.displaySnackBar("Verification Failed: ${e.message}", context,
            isError: true);
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        Navigator.pop(context);
        // Navigate to OTP Screen
        Navigator.push(
            context,
            cMethods.createRoute(OtpVerificationScreen(
              verificationId: verificationId,
              phoneNumber: phoneTextEditingController.text.trim(),
            )));
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ]),
                  child: Column(
                    children: [
                      if (!kIsWeb)
                        Image.asset(
                          "assets/images/logo.png",
                          height: 100,
                        ),
                      const SizedBox(height: 20),
                      Text(
                        "Login",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Phone Field
                      TextField(
                        controller: phoneTextEditingController,
                        keyboardType: TextInputType.phone,
                        style: GoogleFonts.poppins(
                            color: _textColor, fontSize: 14),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _inputColor,
                          hintText: "Phone Number",
                          hintStyle: GoogleFonts.poppins(
                              color: _hintColor, fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: _accentColor, width: 2.0),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            // Phone Login
                            validatePhone();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            overlayColor: Colors.white.withOpacity(0.1),
                          ),
                          child: Text(
                            "Login",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 30),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: GoogleFonts.poppins(
                                color: _hintColor, fontSize: 13),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(context,
                                  cMethods.createRoute(SignUpScreen()));
                            },
                            child: Text(
                              "Sign Up",
                              style: GoogleFonts.poppins(
                                  color: Colors.blue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
