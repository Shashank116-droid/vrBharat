import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NewTripScreen extends StatefulWidget {
  final String rideRequestId;

  const NewTripScreen({super.key, required this.rideRequestId});

  @override
  State<NewTripScreen> createState() => _NewTripScreenState();
}

class _NewTripScreenState extends State<NewTripScreen> {
  String pickupAddress = "Fetching Address...";
  String dropOffAddress = "Fetching Address...";

  String driverName = "";
  String driverPhone = "";
  String driverCollege = "";
  String driverPhoto = "";

  // Design configuration
  final Color _cardColor = const Color(0xFF181820);
  final Color _textColor = Colors.white;
  final Color _secondaryTextColor = Colors.white54;
  final Color _acceptColor = Colors.green;
  final Color _declineColor = Colors.redAccent;

  @override
  void initState() {
    super.initState();
    getRideDetails();
    getDriverDetails();
  }

  Future<void> getDriverDetails() async {
    var snap = await FirebaseFirestore.instance
        .collection("drivers")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();

    if (snap.exists) {
      setState(() {
        driverName = (snap.data() as Map)["name"] ?? "Driver";
        driverPhone = (snap.data() as Map)["phone"] ?? "";
        driverCollege =
            (snap.data() as Map)["collegeName"] ??
            "College Not Found"; // Ensure this matches signup
        print(
          "DEBUG: Fetched Driver Info: Name=$driverName, Phone=$driverPhone, College=$driverCollege",
        );
        // driverPhoto = (snap.data() as Map)["photoUrl"];
      });
    }
  }

  @override
  void dispose() {
    FlutterRingtonePlayer().stop(); // Stop sound when dialog closes
    super.dispose();
  }

  void getRideDetails() {
    // We already have the rideRequest ID. Now fetch details from "rideRequests" collection in Firestore
    FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(widget.rideRequestId)
        .get()
        .then((snap) {
          if (snap.exists) {
            Map<String, dynamic> data = snap.data() as Map<String, dynamic>;
            setState(() {
              pickupAddress = data["pickup_address"] ?? "Unknown Pickup";
              dropOffAddress = data["dropoff_address"] ?? "Unknown Destination";
            });
          }
        });
  }

  Future<void> acceptRideRequest() async {
    // 0. Ensure driver details are loaded
    if (driverName.isEmpty) {
      await getDriverDetails(); // Wait for it
    }

    // DEBUG: Show what data is being sent
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Accepting as: $driverName, $driverPhone, $driverCollege",
        ),
        duration: const Duration(seconds: 4),
      ),
    );

    // 1. Update rideRequest status to "accepted" in Firestore
    FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(widget.rideRequestId)
        .update({
          "status": "accepted",
          "driver_name": driverName,
          "driver_phone": driverPhone,
          "driver_id": FirebaseAuth.instance.currentUser!.uid,
          "driver_college": driverCollege,
        });

    print(
      "DEBUG: Updated RideRequest with Driver Info: Name=$driverName, College=$driverCollege",
    );

    // 2. Close Dialog
    Navigator.pop(context);

    // 3. Navigate to Trip Screen (Map) - To be implemented next
    // For now, just show a snackbar or print
    print("Ride Accepted by $driverName");
  }

  void declineRideRequest() {
    // Just close the dialog.
    // In a real app, you might want to remove this driver from the request queue on server
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 18,
              spreadRadius: 2,
              offset: Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon / Header
              const Icon(Icons.directions_car, size: 60, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                "New Ride Request",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 24),

              // Pickup
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.my_location, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      pickupAddress,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Dropoff
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      dropOffAddress,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: declineRideRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _declineColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        "Decline",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: acceptRideRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _acceptColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: Text(
                        "Accept",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
