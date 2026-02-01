import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:jinete/pages/dashboard.dart'; // Added
import 'package:jinete/widgets/loading_dialog.dart';
import '../methods/common_methods.dart';

class IdUploadScreen extends StatefulWidget {
  const IdUploadScreen({super.key});

  @override
  State<IdUploadScreen> createState() => _IdUploadScreenState();
}

class _IdUploadScreenState extends State<IdUploadScreen> {
  XFile? imageFile;
  CommonMethods cMethods = CommonMethods();

  // Pick Image
  Future<void> pickImage(ImageSource source) async {
    try {
      final pickedFile = await ImagePicker().pickImage(source: source);
      if (pickedFile != null) {
        setState(() {
          imageFile = pickedFile;
        });
      }
    } catch (e) {
      cMethods.displaySnackBar("Error picking image: $e", context,
          isError: true);
    }
  }

  // Upload Logic
  Future<void> uploadIdCard() async {
    if (imageFile == null) {
      cMethods.displaySnackBar("Please select an image first.", context,
          isError: true);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Uploading ID Card..."),
    );

    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;
      String fileName = "id_card";

      // 1. Check Previous Status
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection("users").doc(uid).get();

      bool isReupload = false;
      if (userDoc.exists) {
        String currentStatus =
            (userDoc.data() as Map)["verificationStatus"] ?? "";
        if (currentStatus == "rejected") {
          isReupload = true;
        }
      }

      Reference storageRef = FirebaseStorage.instance
          .ref()
          .child("student_ids")
          .child(uid)
          .child(fileName);

      UploadTask uploadTask = storageRef.putFile(File(imageFile!.path));
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      Map<String, dynamic> updateData = {
        "documents.studentIdCard": downloadUrl,
        "verified": false, // Initial state for Admin Panel
        "verificationStatus": "pending", // Internal UI state
        "studentVerificationStatus": "pending", // Schema Sync
        "profileCompleted": true,
      };

      // 2. Set strict flag if re-uploading
      if (isReupload) {
        updateData["hasPriorRejection"] = true;
      }

      await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .update(updateData);

      if (!mounted) return;
      Navigator.pop(context); // Close dialog

      // Navigate to Home
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (c) => const Dashboard()),
        (route) => false,
      );

      cMethods.displaySnackBar(
          "ID Uploaded Successfully. Verification Pending.", context);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      cMethods.displaySnackBar("Upload Failed: $e", context, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101015),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101015),
        title: Text("Upload ID Card",
            style: GoogleFonts.poppins(color: Colors.white)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Verify Your Identity",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Please upload a clear photo of your College ID Card for verification.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white54),
              ),
              const SizedBox(height: 30),
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF181820),
                    builder: (context) => SafeArea(
                      child: Wrap(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.camera_alt,
                                color: Colors.white),
                            title: Text("Camera",
                                style:
                                    GoogleFonts.poppins(color: Colors.white)),
                            onTap: () {
                              Navigator.pop(context);
                              pickImage(ImageSource.camera);
                            },
                          ),
                          ListTile(
                            leading:
                                const Icon(Icons.image, color: Colors.white),
                            title: Text("Gallery",
                                style:
                                    GoogleFonts.poppins(color: Colors.white)),
                            onTap: () {
                              Navigator.pop(context);
                              pickImage(ImageSource.gallery);
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181820),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  child: imageFile != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(imageFile!.path),
                            fit: BoxFit.cover,
                          ),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_a_photo,
                                size: 50, color: Colors.white54),
                            const SizedBox(height: 10),
                            Text("Tap to upload",
                                style:
                                    GoogleFonts.poppins(color: Colors.white54)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: uploadIdCard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B00),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    "Submit for Verification",
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
