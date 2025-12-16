import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete/authentication/signup_screen.dart';
import 'package:jinete/methods/common_methods.dart';
import 'package:jinete/pages/dashboard.dart'; // Added this import
import 'package:jinete/widgets/loading_dialog.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String verificationId;
  final String phoneNumber;
  final Map<String, dynamic>? signUpData; // Added for new user creation

  const OtpVerificationScreen({
    super.key,
    required this.verificationId,
    required this.phoneNumber,
    this.isLinking = false,
    this.signUpData,
  });

  final bool isLinking;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  TextEditingController otpTextEditingController = TextEditingController();
  CommonMethods cMethods = CommonMethods();

  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _inputColor = const Color(0xFF252530);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;
  final Color _hintColor = Colors.white54;

  void verifyOtp() async {
    String otpCode = otpTextEditingController.text.trim();

    if (otpCode.isEmpty || otpCode.length < 6) {
      cMethods.displaySnackBar("Please enter valid 6-digit OTP", context,
          isError: true);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Verifying OTP..."),
    );

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otpCode,
      );

      if (widget.isLinking) {
        // Link to current user
        User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await currentUser.linkWithCredential(credential);
          // Success linking
          if (!mounted) return;
          Navigator.pop(context); // Close Dialog

          cMethods.displaySnackBar("Phone Verified & Linked!", context);

          // Go to Home (as Signup is complete)
          Navigator.pushAndRemoveUntil(
              context, cMethods.createRoute(Dashboard()), (route) => false);
        }
      } else {
        // Normal Sign In OR New User Creation
        UserCredential userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);

        if (userCredential.user != null) {
          if (widget.signUpData != null) {
            // This is a NEW user flow from SignUpScreen
            await createNewUserRecord(userCredential.user!);
          } else {
            // Existing user logic
            checkUserInFirestore(userCredential.user!);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close Dialog

      String msg = e.message ?? "An error occurred";
      if (e.code == 'credential-already-in-use') {
        msg = "This phone number is already associated with another account.";
      } else if (e.code == 'invalid-verification-code') {
        msg = "Invalid OTP. Please check and try again.";
      }

      cMethods.displaySnackBar(msg, context, isError: true);
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context); // Close Dialog
      cMethods.displaySnackBar("Error: ${error.toString()}", context,
          isError: true);
    }
  }

  Future<void> createNewUserRecord(User firebaseUser) async {
    try {
      Map<String, dynamic> userDataMap = Map.from(widget.signUpData!);
      userDataMap["id"] = firebaseUser.uid;

      // Ensure phone number matches authenticated number
      userDataMap["phone"] = firebaseUser.phoneNumber ?? widget.phoneNumber;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .set(userDataMap);

      if (!mounted) return;
      Navigator.pop(context); // Close dialog

      cMethods.displaySnackBar("Account Created Successfully!", context);

      Navigator.pushAndRemoveUntil(
          context, cMethods.createRoute(Dashboard()), (route) => false);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      cMethods.displaySnackBar(
          "Error creating profile: ${e.toString()}", context,
          isError: true);
    }
  }

  void checkUserInFirestore(User firebaseUser) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .get();

      if (!mounted) return;
      Navigator.pop(context); // Close dialog

      if (userDoc.exists) {
        // User exists, go to Home
        Map<String, dynamic>? userData =
            userDoc.data() as Map<String, dynamic>?;

        if (userData != null && userData["blockStatus"] == "no") {
          Navigator.pushAndRemoveUntil(
              context, cMethods.createRoute(Dashboard()), (route) => false);
        } else {
          FirebaseAuth.instance.signOut();
          cMethods.displaySnackBar("Your are Blocked. Contact Admin.", context,
              isError: true);
        }
      } else {
        // User authenticated but no record found (Shouldn't happen with new flow, but safe fallback)
        FirebaseAuth.instance.signOut();
        cMethods.displaySnackBar("No account found. Please Sign Up.", context,
            isError: true);
        Navigator.pushAndRemoveUntil(
            context,
            cMethods.createRoute(SignUpScreen(phoneNumber: widget.phoneNumber)),
            (route) => false);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      cMethods.displaySnackBar(
          "Error fetching profile: ${e.toString()}", context,
          isError: true);
    }
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
                // Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: _accentColor, width: 2),
                  ),
                  child: Icon(
                    Icons.phonelink_ring_outlined,
                    size: 60,
                    color: _accentColor,
                  ),
                ),

                const SizedBox(height: 32),

                Text(
                  "Verification",
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Enter the 6-digit code sent to\n${widget.phoneNumber}",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _hintColor,
                  ),
                ),

                const SizedBox(height: 32),

                // OTP Field
                TextField(
                  controller: otpTextEditingController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 24,
                      letterSpacing: 4,
                      fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: _inputColor,
                    hintText: "Wait for sms...",
                    hintStyle: GoogleFonts.poppins(
                        color: Colors.white24, fontSize: 16, letterSpacing: 1),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _accentColor, width: 1.5),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Verify Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      verifyOtp();
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

                TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text(
                      "Edit Phone Number",
                      style: GoogleFonts.poppins(color: Colors.blueAccent),
                    ))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
