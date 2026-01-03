import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete/widgets/loading_dialog.dart';

import '../methods/common_methods.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  final String? phoneNumber;
  const SignUpScreen({super.key, this.phoneNumber});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  TextEditingController userNameTextEditingController = TextEditingController();
  TextEditingController userPhoneTextEditingController =
      TextEditingController();
  TextEditingController collegeNameTextEditingController =
      TextEditingController(); // Added
  TextEditingController collegeIdTextEditingController =
      TextEditingController();
  TextEditingController emailTextEditingController =
      TextEditingController(); // Added
  CommonMethods cMethods = CommonMethods();

  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _inputColor = const Color(0xFF252530);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;
  final Color _hintColor = Colors.white54;

  @override
  void initState() {
    super.initState();
    if (widget.phoneNumber != null) {
      userPhoneTextEditingController.text = widget.phoneNumber!;
    }
  }

  void checkIfNetworkIsAvailable() {
    cMethods.checkConnectivity(context);
    signUpFormValidation();
  }

  void signUpFormValidation() {
    if (userNameTextEditingController.text.trim().length < 3) {
      cMethods.displaySnackBar(
          "Your Name must contain at least 4 characters or more", context,
          isError: true);
    } else if (collegeNameTextEditingController.text.trim().length < 3) {
      // Validation for College Name
      cMethods.displaySnackBar("Please Provide a valid College Name", context,
          isError: true);
    } else if (collegeIdTextEditingController.text.trim().isEmpty) {
      cMethods.displaySnackBar(
          "Please provide your College Roll Number", context,
          isError: true);
    } else if (!emailTextEditingController.text.contains("@")) {
      // Basic Email Validation
      cMethods.displaySnackBar("Please provide a valid Email Address", context,
          isError: true);
    } else if (userPhoneTextEditingController.text.trim().length < 9) {
      cMethods.displaySnackBar(
          "Your Phone Number should contain at least 10 characters", context,
          isError: true);
    } else {
      // Proceed to Phone Verification
      verifyPhoneNumberForSignUp();
    }
  }

  void verifyPhoneNumberForSignUp() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Checking details..."),
    );

    String phoneNumber = userPhoneTextEditingController.text.trim();
    if (!phoneNumber.startsWith("+")) {
      phoneNumber = "+91$phoneNumber";
    }

    // Check if phone number already exists in Firestore
    try {
      final QuerySnapshot phoneQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .get();

      if (phoneQuery.docs.isNotEmpty) {
        if (!mounted) return;
        Navigator.pop(context); // Close loading dialog
        cMethods.displaySnackBar(
            "This phone number is already registered. Please Login.", context,
            isError: true);
        return;
      }
    } catch (errorMessage) {
      if (!mounted) return;
      Navigator.pop(context);
      cMethods.displaySnackBar(errorMessage.toString(), context, isError: true);
      return;
    }

    if (!mounted) return;
    Navigator.pop(context); // Close "Checking details..."

    // Start Phone Verification
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Sending OTP to $phoneNumber..."),
    );

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-verification (rare in this flow, but handled)
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

        // Prepare data to pass to OTP screen
        Map<String, dynamic> signUpData = {
          "fullName": userNameTextEditingController.text.trim(),
          "phoneNumber": phoneNumber,
          "email": emailTextEditingController.text.trim(),
          "collegeEmail":
              emailTextEditingController.text.trim(), // Added per schema
          "collegeName": collegeNameTextEditingController.text.trim(),
          "studentId": collegeIdTextEditingController.text.trim(),
          "blockStatus": "no",

          // Default Schema Fields
          "driverVerificationStatus": "not_applied",
          "userType": "passenger",
          "rating": 0,
          "totalRides": 0,
          "isActive": true,
          "profileCompleted": false,
          "studentVerificationStatus": "pending",
        };

        // Navigate to OTP Screen with signUpData
        Navigator.push(
            context,
            cMethods.createRoute(OtpVerificationScreen(
              verificationId: verificationId,
              phoneNumber: phoneNumber,
              signUpData: signUpData,
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
                          "Sign Up",
                          style: GoogleFonts.poppins(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Decoration line
                        Container(
                          width: 50,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(2)),
                        ),

                        const SizedBox(height: 32),

                        // Name
                        TextField(
                          controller: userNameTextEditingController,
                          keyboardType: TextInputType.text,
                          style: GoogleFonts.poppins(
                              color: _textColor, fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _inputColor,
                            hintText: "Full Name",
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
                                  BorderSide(color: _accentColor, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // College Name (Added)
                        TextField(
                          controller: collegeNameTextEditingController,
                          keyboardType: TextInputType.text,
                          style: GoogleFonts.poppins(
                              color: _textColor, fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _inputColor,
                            hintText: "College Name",
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
                                  BorderSide(color: _accentColor, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // College ID
                        TextField(
                          controller: collegeIdTextEditingController,
                          keyboardType: TextInputType.text,
                          style: GoogleFonts.poppins(
                              color: _textColor, fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _inputColor,
                            hintText: "College Roll Number",
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
                                  BorderSide(color: _accentColor, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Email (Added)
                        TextField(
                          controller: emailTextEditingController,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.poppins(
                              color: _textColor, fontSize: 14),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: _inputColor,
                            hintText: "Email Address",
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
                                  BorderSide(color: _accentColor, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Phone
                        TextField(
                          controller: userPhoneTextEditingController,
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
                                  BorderSide(color: _accentColor, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Button
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
                              overlayColor: Colors.white.withOpacity(0.1),
                            ),
                            child: Text(
                              "Create Account",
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
                              "Already have an account? ",
                              style: GoogleFonts.poppins(
                                  color: _hintColor, fontSize: 13),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(context,
                                    cMethods.createRoute(LoginScreen()));
                              },
                              child: Text(
                                "Login",
                                style: GoogleFonts.poppins(
                                    color: Colors.blue,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        )
                      ],
                    ))
              ],
            ),
          ),
        ),
      ),
    );
  }
}
