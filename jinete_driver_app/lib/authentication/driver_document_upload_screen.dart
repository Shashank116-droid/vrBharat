import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jinete_driver_app/widgets/loading_dialog.dart';
import 'package:jinete_driver_app/pages/dashboard.dart';

class DriverDocumentUploadScreen extends StatefulWidget {
  final String driverId;

  const DriverDocumentUploadScreen({super.key, required this.driverId});

  @override
  State<DriverDocumentUploadScreen> createState() =>
      _DriverDocumentUploadScreenState();
}

class _DriverDocumentUploadScreenState
    extends State<DriverDocumentUploadScreen> {
  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;

  final ImagePicker _picker = ImagePicker();

  // Status for each document: null = not uploaded, String = URL
  String? idCardUrl;
  String? licenseUrl;
  String? rcUrl;
  String? insuranceUrl;

  Future<void> pickAndUploadImage(String docType) async {
    final XFile? imageFile = await _picker.pickImage(
      source: ImageSource.gallery,
    );

    if (imageFile != null) {
      String fileName = "";

      switch (docType) {
        case "ID Card":
          fileName = "id_card";
          break;
        case "License":
          fileName = "license";
          break;
        case "RC":
          fileName = "rc";
          break;
        case "Insurance":
          fileName = "insurance";
          break;
      }

      uploadImageToStorage(File(imageFile.path), fileName, docType);
    }
  }

  Future<void> uploadImageToStorage(
    File file,
    String fileName,
    String docType,
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Uploading $docType..."),
    );

    try {
      Reference storageRef = FirebaseStorage.instance
          .ref()
          .child("driver_docs")
          .child(widget.driverId)
          .child(fileName);

      TaskSnapshot snapshot = await storageRef.putFile(file);
      String downloadUrl = await snapshot.ref.getDownloadURL();

      setState(() {
        switch (docType) {
          case "ID Card":
            idCardUrl = downloadUrl;
            break;
          case "License":
            licenseUrl = downloadUrl;
            break;
          case "RC":
            rcUrl = downloadUrl;
            break;
          case "Insurance":
            insuranceUrl = downloadUrl;
            break;
        }
      });

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$docType Uploaded Successfully!")),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload Failed: ${e.toString()}")),
        );
      }
    }
  }

  void saveDriverDocuments() {
    if (idCardUrl == null ||
        licenseUrl == null ||
        rcUrl == null ||
        insuranceUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please upload all documents.")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          LoadingDialog(messageText: "Finalizing Registration..."),
    );

    Map<String, dynamic> docsMap = {
      "id_card": idCardUrl,
      "license": licenseUrl,
      "rc": rcUrl,
      "insurance": insuranceUrl,
    };

    FirebaseFirestore.instance
        .collection("drivers")
        .doc(widget.driverId)
        .update({
          "documents": docsMap,
          "verificationStatus": "pending",
          "profileCompleted": true,
        })
        .then((_) {
          if (mounted) {
            Navigator.pop(context);
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (c) => const Dashboard()),
              (route) => false,
            );
          }
        })
        .catchError((error) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error: ${error.toString()}")),
            );
          }
        });
  }

  Widget buildUploadTile(String title, String? url, VoidCallback onTap) {
    bool isUploaded = url != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUploaded ? Colors.green : Colors.grey.withOpacity(0.2),
        ),
      ),
      child: ListTile(
        leading: Icon(
          isUploaded ? Icons.check_circle : Icons.upload_file,
          color: isUploaded ? Colors.green : _accentColor,
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: isUploaded
            ? const Icon(Icons.edit, color: Colors.grey)
            : const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        title: Text(
          "Upload Documents",
          style: GoogleFonts.poppins(color: _textColor),
        ),
        iconTheme: IconThemeData(color: _textColor),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Verify your Identity",
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Please upload clear photos of the following documents.",
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 30),
              buildUploadTile("Student ID Card", idCardUrl, () {
                pickAndUploadImage("ID Card");
              }),
              buildUploadTile("Driving License", licenseUrl, () {
                pickAndUploadImage("License");
              }),
              buildUploadTile("Vehicle RC", rcUrl, () {
                pickAndUploadImage("RC");
              }),
              buildUploadTile("Vehicle Insurance", insuranceUrl, () {
                pickAndUploadImage("Insurance");
              }),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saveDriverDocuments,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    "Submit Documents",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
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
