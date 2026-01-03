import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jinete_driver_app/authentication/login_screen.dart';
import 'package:jinete_driver_app/authentication/driver_document_upload_screen.dart';

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
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile != null) {
      setState(() {
        imageFile = pickedFile;
        isUploading = true;
      });

      String fileName = FirebaseAuth.instance.currentUser!.uid;
      // Using 'driver_avatars' to separate from user avatars
      Reference storageRef = FirebaseStorage.instance
          .ref()
          .child("driver_avatars")
          .child(fileName);
      UploadTask uploadTask = storageRef.putFile(File(pickedFile.path));

      TaskSnapshot taskSnapshot = await uploadTask;
      String downloadUrl = await taskSnapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection("drivers")
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

  Future<void> _updateSeatCount(int seats) async {
    try {
      await FirebaseFirestore.instance
          .collection("drivers")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .update({"vehicleDetails.seats": seats});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Seat capacity updated to $seats")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error updating seats: $e")));
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
        iconTheme: IconThemeData(color: _textColor),
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("drivers")
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
                "Error: ${snapshot.error}",
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

          var updatedData = snapshot.data!.data() as Map<String, dynamic>;
          String name = updatedData["name"] ?? "Not Set";
          String email = updatedData["email"] ?? "Not Set";
          String phone = updatedData["phoneNumber"] ?? "Not Set";
          String collegeName = updatedData["collegeName"] ?? "Not Set";
          String? photoURL = updatedData["photoURL"];

          Map<String, dynamic> vehicleDetails =
              (updatedData["vehicleDetails"] as Map<String, dynamic>?) ?? {};
          String vehicleType = vehicleDetails["type"] ?? "Not Set";

          // Verification Status Badge
          // Logic to normalize status
          String effectiveStatus =
              (updatedData["verificationStatus"] ?? "pending")
                  .toString()
                  .toLowerCase();
          if (updatedData["verified"] == true ||
              effectiveStatus == "verified") {
            effectiveStatus = "approved";
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                // ... (rest of the top part, I need to match the target content carefully)
                const SizedBox(height: 20),
                // Avatar Section
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
                                  radius: 60,
                                  backgroundColor: Colors.grey,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : CircleAvatar(
                                  radius: 60,
                                  backgroundColor: Colors.grey,
                                  backgroundImage: photoURL != null
                                      ? NetworkImage(photoURL)
                                      : null,
                                  child: photoURL == null
                                      ? const Icon(
                                          Icons.person,
                                          size: 80,
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
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _accentColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _backgroundColor,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                size: 20, // Slightly bigger for driver app
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    color: _textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Driver",
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: _secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 30),

                // Info Cards
                _buildInfoCard(Icons.school, "College", collegeName),
                _buildInfoCard(Icons.phone, "Phone", phone),
                _buildInfoCard(Icons.email, "Email", email),
                _buildInfoCard(
                  Icons.directions_car,
                  "Vehicle Type",
                  vehicleType,
                ),

                // Seat Capacity Selection (Only for Car and Electric)
                if (vehicleType == "Car" || vehicleType == "Electric") ...[
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.event_seat,
                            color: _accentColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Available Seats",
                                style: GoogleFonts.poppins(
                                  color: _secondaryTextColor,
                                  fontSize: 12,
                                ),
                              ),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: vehicleDetails["seats"] is int
                                      ? vehicleDetails["seats"]
                                      : 4, // Default to 4
                                  dropdownColor: _cardColor,
                                  isExpanded: true,
                                  icon: Icon(
                                    Icons.arrow_drop_down,
                                    color: _textColor,
                                  ),
                                  style: GoogleFonts.poppins(
                                    color: _textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  items: List.generate(6, (index) => index + 1)
                                      .map((seats) {
                                        return DropdownMenuItem<int>(
                                          value: seats,
                                          child: Text("$seats Seats"),
                                        );
                                      })
                                      .toList(),
                                  onChanged: (newSeats) {
                                    if (newSeats != null) {
                                      _updateSeatCount(newSeats);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Verification Status Badge
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: _getVerificationColor(
                      effectiveStatus,
                    ).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getVerificationColor(effectiveStatus),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _getVerificationIcon(effectiveStatus),
                        color: _getVerificationColor(effectiveStatus),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _getVerificationText(effectiveStatus),
                        style: GoogleFonts.poppins(
                          color: _getVerificationColor(effectiveStatus),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

                // Upload Again Button (Only if Rejected)
                if (effectiveStatus == "rejected") ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (c) => DriverDocumentUploadScreen(
                                driverId:
                                    FirebaseAuth.instance.currentUser!.uid,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          "Upload Documents Again",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      "Your documents were rejected.\nPlease upload valid documents to proceed.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 30),

                // Sign Out Button
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
                            builder: (c) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.1),
                        side: BorderSide(
                          color: Colors.redAccent.withOpacity(0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Sign Out",
                        style: GoogleFonts.poppins(
                          color: Colors.redAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: _secondaryTextColor,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getVerificationColor(String? status) {
    switch (status) {
      case "approved":
        return Colors.green;
      case "rejected":
        return Colors.red;
      case "pending":
      default:
        return Colors.orange;
    }
  }

  IconData _getVerificationIcon(String? status) {
    switch (status) {
      case "approved":
        return Icons.verified;
      case "rejected":
        return Icons.error_outline;
      case "pending":
      default:
        return Icons.hourglass_empty;
    }
  }

  String _getVerificationText(String status) {
    switch (status) {
      case "approved":
        return "Verified";
      case "rejected":
        return "Action Required";
      case "pending":
      default:
        return "Verification Pending";
    }
  }
}
