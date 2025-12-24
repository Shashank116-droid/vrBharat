import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jinete_driver_app/pages/dashboard.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_database/firebase_database.dart'; // Removed
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete_driver_app/authentication/signup_screen.dart';
import 'package:jinete_driver_app/methods/common_methods.dart';

import 'package:pinput/pinput.dart';

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
  final Color _cardColor = const Color(0xFF181820);
  final Color _inputColor = const Color(0xFF252530);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;
  final Color _hintColor = Colors.white54;

  void checkIfNetworkIsAvailable() async {
    bool isConnected = await cMethods.checkConnectivity(context);
    if (isConnected) {
      signInFormValidation();
    }
  }

  void signInFormValidation() {
    if (phoneTextEditingController.text.trim().length < 10) {
      cMethods.displaySnackBar(
        "Please enter a valid phone number (at least 10 digits)",
        context,
      );
    } else {
      startPhoneAuth();
    }
  }

  void startPhoneAuth() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Sending OTP..."),
    );

    String phoneNumber = phoneTextEditingController.text.trim();
    if (!phoneNumber.startsWith("+")) {
      // Default to India +91 if no code provided, or handle as needed
      phoneNumber = "+91$phoneNumber";
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-resolution (Android mostly)
        await signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (context.mounted) Navigator.pop(context);
        cMethods.displaySnackBar("Verification Failed: ${e.message}", context);
      },
      codeSent: (String verificationId, int? resendToken) {
        if (context.mounted) {
          Navigator.pop(context); // Dismiss loading
          showOTPDialog(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  Future<void> signInWithCredential(PhoneAuthCredential credential) async {
    // Show loading again if coming from OTP dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Verifying & Logging In..."),
    );

    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      if (userCredential.user != null) {
        checkDriverRecord(userCredential.user!);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        cMethods.displaySnackBar("Login Failed: ${e.toString()}", context);
      }
    }
  }

  void checkDriverRecord(User user) {
    FirebaseFirestore.instance
        .collection("drivers")
        .doc(user.uid)
        .get()
        .then((driverSnapshot) {
          if (!context.mounted) return;
          Navigator.pop(context); // Dismiss "Verifying..." dialog

          if (driverSnapshot.exists) {
            if (driverSnapshot.data()!["blockStatus"] == "no") {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (c) => const Dashboard()),
              );
            } else {
              FirebaseAuth.instance.signOut();
              cMethods.displaySnackBar(
                "You are blocked. Please contact admin.",
                context,
              );
            }
          } else {
            // Driver record not found. Check if they are a User (Passenger)
            // Show loading again as we are making another call
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext context) =>
                  LoadingDialog(messageText: "Checking User Account..."),
            );

            FirebaseFirestore.instance
                .collection("users")
                .doc(user.uid)
                .get()
                .then((userSnapshot) {
                  if (!context.mounted) return;
                  Navigator.pop(context); // Dismiss "Checking User..."

                  if (userSnapshot.exists) {
                    // User exists! Fetch details to pre-fill Signup
                    Map<String, dynamic> userProfileData =
                        userSnapshot.data() as Map<String, dynamic>;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => SignUpScreen(
                          existingUser: user,
                          userProfileData: userProfileData,
                        ),
                      ),
                    );
                    cMethods.displaySnackBar(
                      "Welcome! Please complete your Driver Profile.",
                      context,
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => SignUpScreen(existingUser: user),
                      ),
                    );
                  }
                })
                .catchError((error) {
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  cMethods.displaySnackBar(
                    "User DB Error: ${error.toString()}",
                    context,
                  );
                });
          }
        })
        .catchError((error) {
          if (!context.mounted) return;
          Navigator.pop(context);
          cMethods.displaySnackBar("DB Error: ${error.toString()}", context);
        });
  }

  void showOTPDialog(String verificationId) {
    String otpCode = "";
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _cardColor,
          title: Text(
            "Enter OTP",
            style: GoogleFonts.poppins(color: _textColor),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pinput(
                length: 6,
                defaultPinTheme: PinTheme(
                  width: 40,
                  height: 40,
                  textStyle: GoogleFonts.poppins(
                    fontSize: 20,
                    color: _textColor,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: BoxDecoration(
                    color: _inputColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.transparent),
                  ),
                ),
                focusedPinTheme: PinTheme(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _inputColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _accentColor),
                  ),
                ),
                onCompleted: (pin) {
                  otpCode = pin;
                },
                onChanged: (value) {
                  otpCode = value;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(
                "Cancel",
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (otpCode.length == 6) {
                  Navigator.pop(context);
                  PhoneAuthCredential credential = PhoneAuthProvider.credential(
                    verificationId: verificationId,
                    smsCode: otpCode,
                  );
                  signInWithCredential(credential);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: _accentColor),
              child: Text(
                "Verify",
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
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
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      if (!kIsWeb)
                        Image.asset("assets/images/logo.png", height: 100),
                      const SizedBox(height: 20),
                      Text(
                        "Login as a Driver",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Phone Input (Simplified for brevity)
                      TextField(
                        controller: phoneTextEditingController,
                        keyboardType: TextInputType.phone,
                        style: GoogleFonts.poppins(
                          color: _textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _inputColor,
                          hintText: "Phone Number",
                          hintStyle: GoogleFonts.poppins(
                            color: _hintColor,
                            fontSize: 14,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
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
                            borderSide: BorderSide(
                              color: _accentColor,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () {
                            checkIfNetworkIsAvailable();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            "Verify & Login",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: GoogleFonts.poppins(
                              color: _hintColor,
                              fontSize: 13,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => SignUpScreen(),
                                ),
                              );
                            },
                            child: Text(
                              "Sign Up",
                              style: GoogleFonts.poppins(
                                color: Colors.blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
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
