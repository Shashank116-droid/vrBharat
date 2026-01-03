import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jinete/authentication/login_screen.dart';
import 'package:jinete/authentication/id_upload_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _textColor = Colors.white;
  final Color _secondaryTextColor = Colors.white54;
  final Color _accentColor = const Color(0xFFFF6B00);

  XFile? imageFile;
  bool isUploading = false;

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        imageFile = pickedFile;
        isUploading = true;
      });

      String fileName = FirebaseAuth.instance.currentUser!.uid;
      Reference storageRef =
          FirebaseStorage.instance.ref().child("user_avatars").child(fileName);
      UploadTask uploadTask = storageRef.putFile(File(pickedFile.path));

      TaskSnapshot taskSnapshot = await uploadTask;
      String downloadUrl = await taskSnapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection("users")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({"photoURL": downloadUrl});

      setState(() {
        isUploading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Profile Picture Updated!")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          "My Profile",
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: _backgroundColor,
        automaticallyImplyLeading: false, // No back button
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("users")
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error loading profile",
                style: GoogleFonts.poppins(color: _textColor),
              ),
            );
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Text(
                "Profile not found.",
                style: GoogleFonts.poppins(color: _textColor),
              ),
            );
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String name = data["fullName"] ?? "User";
          String email = data["email"] ?? data["collegeEmail"] ?? "";
          String phone = data["phoneNumber"] ?? "";
          String collegeName = data["collegeName"] ?? "";
          String? photoURL = data["photoURL"];

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      if (!isUploading) {
                        _pickAndUploadImage();
                      }
                    },
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _accentColor, width: 2),
                          ),
                          child: isUploading
                              ? const CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.grey,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Colors.grey,
                                  backgroundImage: photoURL != null
                                      ? NetworkImage(photoURL)
                                      : null,
                                  child: photoURL == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 60,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                        ),
                        if (!isUploading)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _accentColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _backgroundColor, width: 2),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    color: _textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Rider",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (data["verified"] == true)
                        ? Colors.green.withOpacity(0.2)
                        : (data["verificationStatus"] == "rejected")
                            ? Colors.red.withOpacity(0.2)
                            : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (data["verified"] == true)
                          ? Colors.green
                          : (data["verificationStatus"] == "rejected")
                              ? Colors.red
                              : Colors.orange,
                    ),
                  ),
                  child: Text(
                    (data["verified"] == true)
                        ? "Verified"
                        : (data["verificationStatus"] == "rejected")
                            ? "Action Required"
                            : "Verification Pending",
                    style: GoogleFonts.poppins(
                      color: (data["verified"] == true)
                          ? Colors.green
                          : (data["verificationStatus"] == "rejected")
                              ? Colors.red
                              : Colors.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                _buildInfoCard(Icons.school, "College", collegeName),
                _buildInfoCard(Icons.phone, "Phone", phone),
                _buildInfoCard(Icons.email, "Email", email),
                if (data["verificationStatus"] == "rejected") ...[
                  const SizedBox(height: 30),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(
                          "Verification Failed. Please upload again.",
                          style: GoogleFonts.poppins(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (c) => const IdUploadScreen()),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              "Upload ID Again",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        FirebaseAuth.instance.signOut();
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (c) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.1),
                        side: BorderSide(
                            color: Colors.redAccent.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Sign Out",
                        style: GoogleFonts.poppins(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _accentColor, size: 24),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.poppins(
                      color: _secondaryTextColor, fontSize: 12)),
              Text(value,
                  style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}
