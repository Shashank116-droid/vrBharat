import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_database/firebase_database.dart'; // Removed
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete_driver_app/widgets/loading_dialog.dart';
import 'package:pinput/pinput.dart';

import '../methods/common_methods.dart';
import 'login_screen.dart';
import 'vehicle_info_screen.dart';

class SignUpScreen extends StatefulWidget {
  final User? existingUser;
  final Map? userProfileData;

  const SignUpScreen({super.key, this.existingUser, this.userProfileData});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  TextEditingController userNameTextEditingController = TextEditingController();
  TextEditingController collegeNameTextEditingController =
      TextEditingController();
  TextEditingController rollNumberTextEditingController =
      TextEditingController();
  TextEditingController userPhoneTextEditingController =
      TextEditingController();
  TextEditingController emailTextEditingController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.userProfileData != null) {
      if (widget.userProfileData!["fullName"] != null) {
        userNameTextEditingController.text = widget.userProfileData!["fullName"]
            .toString();
      }
      if (widget.userProfileData!["collegeName"] != null) {
        collegeNameTextEditingController.text = widget
            .userProfileData!["collegeName"]
            .toString();
      }
      if (widget.userProfileData!["studentId"] != null) {
        rollNumberTextEditingController.text = widget
            .userProfileData!["studentId"]
            .toString();
      }
      if (widget.userProfileData!["phoneNumber"] != null) {
        userPhoneTextEditingController.text = widget
            .userProfileData!["phoneNumber"]
            .toString();
      }
      if (widget.userProfileData!["email"] != null) {
        emailTextEditingController.text = widget.userProfileData!["email"]
            .toString();
      }
    }
    // Also use existingUser phone if available and not in profile data
    if (widget.existingUser != null &&
        userPhoneTextEditingController.text.isEmpty) {
      userPhoneTextEditingController.text =
          widget.existingUser!.phoneNumber ?? "";
    }
  }

  // Remainder of class restored

  CommonMethods cMethods = CommonMethods();

  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _inputColor = const Color(0xFF252530);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;
  final Color _hintColor = Colors.white54;

  void checkIfNetworkIsAvailable() {
    cMethods.checkConnectivity(context);
    signUpFormValidation();
  }

  void signUpFormValidation() {
    if (userNameTextEditingController.text.trim().length < 3) {
      cMethods.displaySnackBar(
        "Your Name must contain at least 4 characters or more",
        context,
      );
    } else if (collegeNameTextEditingController.text.trim().isEmpty) {
      cMethods.displaySnackBar("Please provide your College Name", context);
    } else if (rollNumberTextEditingController.text.trim().isEmpty) {
      cMethods.displaySnackBar("Please provide your Roll Number", context);
    } else if (userPhoneTextEditingController.text.trim().length < 9) {
      cMethods.displaySnackBar(
        "Your Phone Number should contain 10 characters",
        context,
      );
    } else if (!emailTextEditingController.text.contains("@")) {
      cMethods.displaySnackBar("Please enter a valid email", context);
    } else {
      if (widget.existingUser != null) {
        // User already authenticated via Login Screen
        saveDriverInfoToFirestore(widget.existingUser!);
      } else {
        // Fresh Signup - Verify Phone
        startPhoneAuth();
      }
    }
  }

  void startPhoneAuth() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Sending OTP..."),
    );

    String phoneNumber = userPhoneTextEditingController.text.trim();
    if (!phoneNumber.startsWith("+")) {
      // Default to India +91 if not provided
      phoneNumber = "+91$phoneNumber";
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-resolution
        await registerNewDriver(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (context.mounted) Navigator.pop(context);
        cMethods.displaySnackBar("Verification Failed: ${e.message}", context);
      },
      codeSent: (String verificationId, int? resendToken) {
        if (context.mounted) {
          Navigator.pop(context);
          showOTPDialog(verificationId);
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
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
                  registerNewDriver(credential);
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

  Future<void> registerNewDriver(PhoneAuthCredential credential) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Registering Account..."),
    );

    User? userFirebase;
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      userFirebase = userCredential.user;
    } catch (error) {
      if (!context.mounted) return;
      Navigator.pop(context);
      cMethods.displaySnackBar(
        "Registration Error: ${error.toString()}",
        context,
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.pop(context); // Close "Registering Account..."

    if (userFirebase != null) {
      saveDriverInfoToFirestore(userFirebase);
    }
  }

  Future<void> saveDriverInfoToFirestore(User userFirebase) async {
    Map<String, dynamic> driverDataMap = {
      "name": userNameTextEditingController.text.trim(),
      "collegeName": collegeNameTextEditingController.text.trim(),
      "rollNumber": rollNumberTextEditingController.text.trim(),
      "phoneNumber": userPhoneTextEditingController.text.trim(),
      "email": emailTextEditingController.text.trim(),
      "id": userFirebase.uid,
      "blockStatus": "no",
    };

    FirebaseFirestore.instance
        .collection("drivers")
        .doc(userFirebase.uid)
        .set(driverDataMap);

    // Redirect to Vehicle Info Screen
    cMethods.displaySnackBar(
      "Account Created. Please Select Vehicle Type.",
      context,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => VehicleInfoScreen(driverId: userFirebase.uid),
      ),
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
                        "Sign Up as a Driver",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: 50,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Name
                      TextField(
                        controller: userNameTextEditingController,
                        keyboardType: TextInputType.text,
                        style: GoogleFonts.poppins(
                          color: _textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _inputColor,
                          hintText: "Full Name",
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
                      const SizedBox(height: 20),

                      // College Name
                      TextField(
                        controller: collegeNameTextEditingController,
                        keyboardType: TextInputType.text,
                        style: GoogleFonts.poppins(
                          color: _textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _inputColor,
                          hintText: "College Name",
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
                      const SizedBox(height: 20),

                      // Roll Number
                      TextField(
                        controller: rollNumberTextEditingController,
                        keyboardType: TextInputType.text,
                        style: GoogleFonts.poppins(
                          color: _textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _inputColor,
                          hintText: "Roll Number",
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
                      const SizedBox(height: 20),

                      // Phone
                      TextField(
                        controller: userPhoneTextEditingController,
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
                      const SizedBox(height: 20),

                      // Email (Added)
                      TextField(
                        controller: emailTextEditingController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.poppins(
                          color: _textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _inputColor,
                          hintText: "Email",
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

                      // REMOVED EMAIL AND PASSWORD FIELDS
                      const SizedBox(height: 32),

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
                            "Verify & Register",
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
                              color: _hintColor,
                              fontSize: 13,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => LoginScreen(),
                                ),
                              );
                            },
                            child: Text(
                              "Login",
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
