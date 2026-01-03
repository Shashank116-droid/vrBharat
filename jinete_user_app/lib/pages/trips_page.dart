import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _textColor = Colors.white;
  final Color _secondaryTextColor = Colors.white54;
  final Color _accentColor = const Color(0xFFFF6B00);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        title: Text(
          "Trip Activities",
          style: GoogleFonts.poppins(
            color: _textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection("trips")
            .where("riderId", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
            .orderBy("time", descending: true)
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

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey[800]),
                  const SizedBox(height: 16),
                  Text(
                    "No trips yet.",
                    style: GoogleFonts.poppins(
                      color: _secondaryTextColor,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var data =
                  snapshot.data!.docs[index].data();
// Trip record might not have name
              String pickup = data["pickupAddress"] ?? "Unknown";
              String dropoff = data["destinationAddress"] ?? "Unknown";
              String fare = data["paymentAmount"] ?? "0";
              String date = "";

              if (data["time"] != null) {
                try {
                  Timestamp t = data["time"];
                  DateTime dt = t.toDate();
                  date = DateFormat("dd MMM, hh:mm a").format(dt);
                } catch (e) {
                  date = "";
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(date,
                              style: GoogleFonts.poppins(
                                  color: _secondaryTextColor, fontSize: 12)),
                          Text("₹$fare",
                              style: GoogleFonts.poppins(
                                  color: _textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ]),
                    const SizedBox(height: 12),
                    Text("Trip Completed",
                        style: GoogleFonts.poppins(
                            color: _accentColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    _buildLocationRow(Icons.my_location, Colors.green, pickup),
                    const SizedBox(height: 8),
                    _buildLocationRow(Icons.location_on, Colors.red, dropoff),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color iconColor, String text) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style:
                GoogleFonts.poppins(color: _secondaryTextColor, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
