import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:jinete/pages/dashboard.dart';

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
  bool _hasRedirected = false;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
          bottom: TabBar(
            indicatorColor: _accentColor,
            labelColor: _accentColor,
            unselectedLabelColor: _secondaryTextColor,
            tabs: const [
              Tab(text: "Scheduled"),
              Tab(text: "History"),
            ],
          ),
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: TabBarView(
          children: [
            // 1. Upcoming Trips Tab
            _buildUpcomingTrips(),
            // 2. History Tab (Existing Logic)
            _buildHistoryTrips(),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingTrips() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection("bookings")
          .where("riderId", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where("status", whereIn: ["pending", "accepted", "started"])
          .orderBy("tripDate", descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        if (snapshot.hasError) {
          return Center(
              child: Text("Error: ${snapshot.error}",
                  style: GoogleFonts.poppins(color: _textColor)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState("No upcoming trips.");
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var rawData = snapshot.data!.docs[index].data();
            Map<String, dynamic> data = rawData;

            String pickup = "Unknown";
            if (data["pickup"] != null && data["pickup"] is Map) {
              pickup = data["pickup"]["address"] ?? "Unknown";
            }
            String dropoff = "Unknown";
            if (data["destination"] != null && data["destination"] is Map) {
              dropoff = data["destination"]["address"] ?? "Unknown";
            }
            String status = data["status"] ?? "pending";
            int? dateMillis = data["tripDate"];
            String dateStr = "";
            if (dateMillis != null) {
              dateStr = DateFormat("dd MMM, hh:mm a")
                  .format(DateTime.fromMillisecondsSinceEpoch(dateMillis));
            }

            bool isStale = false;
            if (dateMillis != null) {
              final dt = DateTime.fromMillisecondsSinceEpoch(dateMillis);
              // If trip is more than 12 hours in the past, treat as stale/zombie
              if (DateTime.now().difference(dt).inHours > 12) {
                isStale = true;
              }
            }

            if (status == "started" &&
                data["rideRequestId"] != null &&
                !isStale) {
              // Active Ride Banner
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.greenAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.directions_car,
                            color: Colors.greenAccent),
                        const SizedBox(width: 8),
                        Text("Ride in Progress",
                            style: GoogleFonts.poppins(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        const Spacer(),
                        // Dismiss Button for stuck rides
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.white54),
                          onPressed: () async {
                            bool? confirm = await showDialog(
                                context: context,
                                builder: (c) => AlertDialog(
                                      title: const Text("Clear Stuck Ride?"),
                                      content: const Text(
                                          "This will remove this ride from your list."),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(c),
                                            child: const Text("Cancel")),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text("Clear")),
                                      ],
                                    ));
                            if (confirm == true) {
                              FirebaseFirestore.instance
                                  .collection("bookings")
                                  .doc(snapshot.data!.docs[index].id)
                                  .update({"status": "cancelled"});
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Pickup: $pickup",
                      style: GoogleFonts.poppins(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Text(
                        "OTP: ${data["otp"] ?? 'N/A'}",
                        style: GoogleFonts.poppins(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        onPressed: () {
                          String rId = data["rideRequestId"];
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (c) => Dashboard(
                                      initialIndex: 0,
                                      autoStartRideId: rId,
                                    )),
                            (route) => false,
                          );
                        },
                        child: Text("Head to Live Tracking",
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: status == "accepted"
                        ? Colors.green
                        : _accentColor.withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(dateStr,
                            style: GoogleFonts.poppins(
                                color: _textColor,
                                fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == "accepted"
                                ? Colors.green.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: GoogleFonts.poppins(
                                color: status == "accepted"
                                    ? Colors.green
                                    : Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]),
                  const SizedBox(height: 12),
                  _buildLocationRow(Icons.my_location, Colors.green, pickup),
                  const SizedBox(height: 8),
                  _buildLocationRow(Icons.location_on, Colors.red, dropoff),
                  const SizedBox(height: 12),
                  if (status == "accepted" && data["otp"] != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.greenAccent.withOpacity(0.5))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("OTP: ",
                              style:
                                  GoogleFonts.poppins(color: Colors.white70)),
                          Text(data["otp"],
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  letterSpacing: 2)),
                        ],
                      ),
                    ),
                  if (status == "pending")
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: () {
                          // Cancel Logic
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text("Cancel Booking"),
                              content: const Text(
                                  "Are you sure you want to cancel this request?"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const Text("No"),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(c);
                                    FirebaseFirestore.instance
                                        .collection("bookings")
                                        .doc(snapshot.data!.docs[index].id)
                                        .update({
                                      "status": "cancelled",
                                      "cancelledBy": "rider",
                                      "cancelledAt":
                                          FieldValue.serverTimestamp(),
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text("Booking Cancelled")));
                                  },
                                  child: const Text("Yes, Cancel",
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.cancel_outlined,
                            color: Colors.redAccent, size: 20),
                        label: Text("Cancel Request",
                            style: GoogleFonts.poppins(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    )
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryTrips() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
          return _buildEmptyState("No past trips.");
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var data = snapshot.data!.docs[index].data();
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
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.poppins(
              color: _secondaryTextColor,
              fontSize: 16,
            ),
          ),
        ],
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
