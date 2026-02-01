import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:jinete_driver_app/methods/common_methods.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:jinete_driver_app/pages/dashboard.dart';
import 'dart:math';

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
  final Color _accentColor = const Color(0xFFFF6B00); // Jinete Orange

  int seatCapacity = 0;
  String vehicleType = "Car";
  String driverName = "";
  String driverPhone = "";
  String driverCollege = "";

  @override
  void initState() {
    super.initState();
    getDriverDetails();
  }

  Future<void> getDriverDetails() async {
    var snap = await FirebaseFirestore.instance
        .collection("drivers")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();

    if (snap.exists) {
      if (mounted) {
        setState(() {
          driverName = (snap.data() as Map)["name"] ?? "Driver";
          driverPhone =
              (snap.data() as Map)["phone"] ??
              FirebaseAuth.instance.currentUser!.phoneNumber ??
              "";
          driverCollege =
              (snap.data() as Map)["collegeName"] ?? "College Not Found";

          Map<String, dynamic> vDetails =
              (snap.data() as Map)["vehicleDetails"] ?? {};
          vehicleType = vDetails["type"] ?? "Car";
          if (vDetails["seats"] != null) {
            seatCapacity = int.parse(vDetails["seats"].toString());
          } else {
            // Default logic if seats not set
            if (vehicleType == "Bike") {
              seatCapacity = 1;
            } else {
              seatCapacity = 0;
            }
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          title: Text(
            "Trips",
            style: GoogleFonts.poppins(
              color: _textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: _backgroundColor,
          elevation: 0,
          bottom: TabBar(
            labelColor: _accentColor,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _accentColor,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: "Live"),
              Tab(text: "Scheduled"),
              Tab(text: "History"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildRequestsTab(),
            _buildScheduledTab(),
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  // --- SCHEDULED TAB ---
  Widget _buildScheduledTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Pending Booking Requests
          _buildIncomingBookings(),

          Divider(color: Colors.white12, thickness: 1),

          // 2. My Created Scheduled Trips
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "My Upcoming Trips",
              style: GoogleFonts.poppins(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _buildMyScheduledTrips(),
        ],
      ),
    );
  }

  Widget _buildIncomingBookings() {
    String myUid = FirebaseAuth.instance.currentUser!.uid;

    // Outer Stream: Fetch My Scheduled Trips to validate availability
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("scheduled_trips")
          .where("driverId", isEqualTo: myUid)
          .where("status", isEqualTo: "scheduled")
          .snapshots(),
      builder: (context, tripSnapshot) {
        // Collect my trip times
        List<int> myTripTimes = [];
        if (tripSnapshot.hasData) {
          for (var doc in tripSnapshot.data!.docs) {
            var d = doc.data() as Map<String, dynamic>;
            if (d["tripDate"] != null) {
              myTripTimes.add(d["tripDate"] as int);
            }
          }
        }

        // Inner Stream: Fetch Bookings
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("bookings")
              .where("driverId", whereIn: [myUid, "waiting"])
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return SizedBox();

            // Client-side filtering
            var docs = snapshot.data!.docs.where((d) {
              var data = d.data() as Map<String, dynamic>;
              String status = data["status"] ?? "";
              String bDriverId = data["driverId"] ?? "";
              int bTime = data["tripDate"] ?? 0;
              List rejectedBy = data["rejectedBy"] ?? [];

              // 0. Rejection Check (Hide if I already rejected it)
              if (rejectedBy.contains(myUid)) return false;

              // 1. Status Check
              if (!["pending", "accepted"].contains(status)) return false;

              // 2. Ownership Check (Accepted/Assigned trips)
              if (bDriverId == myUid) return true;

              // 3. Time Window Check for 'waiting' requests (Broadcasts)
              if (bDriverId == "waiting") {
                // Return true if any of my trips are within +/- 30 mins
                bool matchesSchedule = myTripTimes.any((myTime) {
                  int diff = (myTime - bTime).abs();
                  // Debug Log for verification
                  print(
                    "DEBUG: Checking Schedule Match - MyTime: $myTime, BookTime: $bTime, Diff: $diff",
                  );
                  // 30 mins = 1,800,000 ms.
                  // A 24-hour difference is 86,400,000 ms, so this safely excludes trips on different dates.
                  return diff <= 1800000;
                });
                return matchesSchedule;
              }

              return false;
            }).toList();

            if (docs.isEmpty) return SizedBox();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    "New Booking Requests",
                    style: GoogleFonts.poppins(
                      color: _accentColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    var data = doc.data() as Map<String, dynamic>;
                    return Container(
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _accentColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: Colors.amber.withOpacity(0.6),
                              ),
                            ),
                            child: Text(
                              "Trip Time: ${data["tripDate"] != null ? DateFormat('EEE, MMM d • h:mm a').format(DateTime.fromMillisecondsSinceEpoch(data["tripDate"])) : 'N/A'}",
                              style: GoogleFonts.poppins(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            "Rider: ${data['riderName']}",
                            style: GoogleFonts.poppins(
                              color: _textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "From: ${data['pickup']['address']}",
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            "To: ${data['destination']['address']}",
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          SizedBox(height: 10),
                          data['status'] == 'accepted'
                              ? Column(
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _accentColor,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                        onPressed: () async {
                                          String newRideId = FirebaseFirestore
                                              .instance
                                              .collection("rideRequests")
                                              .doc()
                                              .id;

                                          // 1. Create Live Ride Request
                                          _startSelfManagedTrip(
                                            doc.id,
                                            data,
                                            newRideId,
                                          );
                                        },
                                        child: Text(
                                          "Start Ride",
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(
                                            color: Colors.redAccent,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                        onPressed: () async {
                                          // Cancel Logic
                                          await FirebaseFirestore.instance
                                              .collection("bookings")
                                              .doc(doc.id)
                                              .update({
                                                "status": "cancelled",
                                                "cancelledBy": "driver",
                                                "cancelledAt":
                                                    FieldValue.serverTimestamp(),
                                              });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text("Trip Cancelled"),
                                              ),
                                            );
                                          }
                                        },
                                        child: Text(
                                          "Cancel Trip",
                                          style: GoogleFonts.poppins(
                                            color: Colors.redAccent,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        onPressed: () => acceptBooking(doc.id),
                                        child: Text("Accept"),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        onPressed: () => declineBooking(doc.id),
                                        child: Text("Decline"),
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Helper moved out or refined in future steps, but for now inline replacement
  Future<void> _startSelfManagedTrip(
    String docId,
    Map<String, dynamic> data,
    String newRideId,
  ) async {
    // 1. Create Live Ride Request
    String otpCode = data["otp"] ?? (Random().nextInt(9000) + 1000).toString();

    // 1. Create Live Ride Request
    await FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(newRideId)
        .set({
          "driver_id": FirebaseAuth.instance.currentUser!.uid,
          "rider_id": data["riderId"],
          "driver_name": data["driverName"] ?? driverName,
          "driver_phone":
              data["driverPhone"] ??
              driverPhone ??
              FirebaseAuth.instance.currentUser!.phoneNumber,
          "driver_college": data["driverCollege"] ?? driverCollege,
          "otp": otpCode,
          "rider_name":
              data["riderName"] ?? data["userName"] ?? data["name"] ?? "Rider",
          "rider_phone":
              data["riderPhone"] ?? data["userPhone"] ?? data["phone"] ?? "",
          "rider_college":
              data["riderCollege"] ??
              data["userCollege"] ??
              "College Info Unavailable",
          "pickup": data["pickup"],
          "destination": data["destination"],
          "status": "accepted", // Triggers 'Driver Arriving' UI
          "created_at": FieldValue.serverTimestamp(),
          "tripDate": data["tripDate"],
          "fare_offer":
              data["fare"] ?? data["amount"] ?? data["fare_offer"] ?? "0",
        });

    // 2. Update Booking (Link to Live Ride)
    await FirebaseFirestore.instance.collection("bookings").doc(docId).update({
      "status": "started",
      "rideRequestId": newRideId,
    });

    // 3. Update Online Driver Status (to ensure HomePage sync)
    await FirebaseFirestore.instance
        .collection("online_drivers")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .update({"newRideStatus": "accepted"});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Ride Started! Switching to Live Mode...")),
    );

    // 4. Force Navigate to Dashboard (Fresh State with Bottom Nav)
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (c) => const Dashboard()),
        (route) => false,
      );
    }
  }

  Widget _buildMyScheduledTrips() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("scheduled_trips")
          .where("driverId", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where("status", isEqualTo: "scheduled")
          .orderBy(
            "tripDate",
          ) // Ensure index exists or remove order by if needed
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return Center(child: CircularProgressIndicator(color: _accentColor));
        if (snapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(30.0),
              child: Text(
                "No upcoming trips scheduled.",
                style: GoogleFonts.poppins(color: Colors.white38),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            var data = doc.data() as Map<String, dynamic>;
            int? date = data['tripDate'];
            String timeStr = date != null
                ? DateFormat(
                    'dd MMM, hh:mm a',
                  ).format(DateTime.fromMillisecondsSinceEpoch(date))
                : "";

            return Container(
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        timeStr,
                        style: GoogleFonts.poppins(
                          color: _accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Icon(
                        Icons.calendar_today,
                        color: Colors.white54,
                        size: 16,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  _buildLocationRow(
                    Icons.my_location,
                    Colors.green,
                    data['pickup']['address'] ?? "",
                  ),
                  SizedBox(height: 8),
                  _buildLocationRow(
                    Icons.location_on,
                    Colors.red,
                    data['destination']['address'] ?? "",
                  ),
                  SizedBox(height: 12),
                  // Delete/Cancel Option
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        // 1. Update Trip Status (Logic consistency)
                        await FirebaseFirestore.instance
                            .collection("scheduled_trips")
                            .doc(doc.id)
                            .update({
                              "status": "cancelled",
                              "cancelledBy": "driver",
                              "cancelledAt": FieldValue.serverTimestamp(),
                            });

                        // 2. Notify Users via Booking Update
                        // Find all bookings for this trip
                        var bookingsQuery = await FirebaseFirestore.instance
                            .collection("bookings")
                            // We need to link bookings to scheduledTripId if possible,
                            // or match by driverId + time.
                            // The booking creation (createOpenBooking or Accept) might not link 'scheduledTripId' perfectly if it was a broadcast.
                            // But usually, if it's a specific scheduled trip, the booking has 'driverId'.
                            .where(
                              "driverId",
                              isEqualTo: FirebaseAuth.instance.currentUser!.uid,
                            )
                            .where("tripDate", isEqualTo: data["tripDate"])
                            .get();

                        for (var b in bookingsQuery.docs) {
                          b.reference.update({
                            "status": "cancelled",
                            "cancelledBy": "driver",
                            "cancelledAt": FieldValue.serverTimestamp(),
                          });
                        }

                        // 3. Delete Confirmation Logic
                        // We shouldn't delete immediately if we want to keep history,
                        // but strictly speaking 'Unpublish' means delete.
                        // We delay delete to ensure triggers fire.
                        Future.delayed(const Duration(seconds: 3), () {
                          FirebaseFirestore.instance
                              .collection("scheduled_trips")
                              .doc(doc.id)
                              .delete();
                        });

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Trip Cancelled")),
                          );
                        }
                      },
                      child: Text(
                        "Cancel Trip",
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void acceptBooking(String docId) {
    String otpCode = (Random().nextInt(9000) + 1000).toString();
    FirebaseFirestore.instance.collection("bookings").doc(docId).update({
      "status": "accepted",
      "driverId": FirebaseAuth.instance.currentUser!.uid,
      "driverName": driverName,
      "driverPhone": driverPhone,
      "driverCollege": driverCollege,
      "otp": otpCode,
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Booking Accepted!")));
  }

  void declineBooking(String docId) async {
    var doc = await FirebaseFirestore.instance
        .collection("bookings")
        .doc(docId)
        .get();

    if (doc.exists) {
      String bDriverId = (doc.data() as Map)["driverId"] ?? "";
      if (bDriverId == "waiting") {
        // Broadcast Request: Just ignore it for this driver
        await FirebaseFirestore.instance
            .collection("bookings")
            .doc(docId)
            .update({
              "rejectedBy": FieldValue.arrayUnion([
                FirebaseAuth.instance.currentUser!.uid,
              ]),
            });
      } else {
        // Direct Request: Reject it
        await FirebaseFirestore.instance
            .collection("bookings")
            .doc(docId)
            .update({"status": "rejected"});
      }
    }
  }

  // --- EXISTING LIVE TAB ---
  Widget _buildRequestsTab() {
    String currentDriverId = FirebaseAuth.instance.currentUser!.uid;

    // Stream 1: Check Online Status & New Ride ID
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("online_drivers")
          .doc(currentDriverId)
          .snapshots(),
      builder: (context, onlineSnap) {
        if (!onlineSnap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        // Stream 2: Check Active Rides Count
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection("rideRequests")
              .where("driver_id", isEqualTo: currentDriverId)
              .where("status", whereIn: ["accepted", "arrived", "ontrip"])
              .snapshots(),
          builder: (context, activeTripsSnap) {
            if (!activeTripsSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            int activeRidesCount = activeTripsSnap.data!.docs.length;

            // Logic: If Bike and already has 1 active ride, HIDE new requests.
            if ((vehicleType == "Bike") && activeRidesCount >= 1) {
              return _buildNoRequestsView();
            }

            if (!onlineSnap.data!.exists) {
              return _buildNoRequestsView();
            }

            Map<String, dynamic> data =
                onlineSnap.data!.data() as Map<String, dynamic>;
            String newRideStatus = data["newRideStatus"] ?? "idle";

            if (newRideStatus == "idle") {
              return _buildNoRequestsView();
            } else {
              return _buildRideRequestCard(newRideStatus);
            }
          },
        );
      },
    );
  }

  Widget _buildNoRequestsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_taxi, size: 80, color: Colors.grey[800]),
          const SizedBox(height: 16),
          Text(
            "Looking for nearby passengers...",
            style: GoogleFonts.poppins(
              color: _secondaryTextColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideRequestCard(String rideRequestId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection("rideRequests")
          .doc(rideRequestId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.data!.exists) {
          // Request might have been cancelled or deleted
          return _buildNoRequestsView();
        }

        Map<String, dynamic> rideData =
            snapshot.data!.data() as Map<String, dynamic>;

        String pickup = rideData["pickup_address"] ?? "Unknown Pickup";
        String dropoff = rideData["dropoff_address"] ?? "Unknown Dropoff";
        String fare = rideData["fare_offer"] ?? "0";
        int distanceMeters = rideData["distance_value"] ?? 0;

        print("DEBUG: Driver App Card - Pickup: $pickup, Dropoff: $dropoff");

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: _accentColor.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "New Ride Request",
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              // Dynamic Address Logic
              // Dynamic Address Logic
              // Dynamic Address Logic
              (pickup == "Current Location" ||
                      pickup == "Unknown Pickup" ||
                      pickup.contains(
                        RegExp(r'[0-9]+\.[0-9]+, [0-9]+\.[0-9]+'),
                      ))
                  ? FutureBuilder<String>(
                      future:
                          CommonMethods.convertGeoGraphicCoOrdinatesToHumanReadableAddress(
                            LatLng(
                              double.parse(
                                rideData["pickup"]["latitude"].toString(),
                              ),
                              double.parse(
                                rideData["pickup"]["longitude"].toString(),
                              ),
                            ),
                          ),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return _buildLocationRow(
                            Icons.my_location,
                            Colors.green,
                            "Error fetching address",
                          );
                        }
                        return _buildLocationRow(
                          Icons.my_location,
                          Colors.green,
                          snap.data ?? "Fetching Address...",
                        );
                      },
                    )
                  : _buildLocationRow(Icons.my_location, Colors.green, pickup),

              const SizedBox(height: 16),
              _buildLocationRow(Icons.location_on, Colors.red, dropoff),
              const SizedBox(height: 20),
              Divider(color: Colors.white24),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Fare Offer",
                    style: GoogleFonts.poppins(
                      color: _secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    "₹$fare",
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              Row(
                children: [
                  // Counter Offer Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        showCounterOfferDialog(
                          context,
                          rideRequestId,
                          distanceMeters,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        "Counter",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Decline Logic: Update cloud to idle
                        FirebaseFirestore.instance
                            .collection("online_drivers")
                            .doc(FirebaseAuth.instance.currentUser!.uid)
                            .update({"newRideStatus": "idle"});
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        "Decline",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        // Accept Logic

                        // Check if Seats are set (Car/Electric)
                        if ((vehicleType == "Car" ||
                                vehicleType == "Electric") &&
                            seatCapacity <= 0) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Colors.red,
                                content: Text(
                                  "Please set 'Available Seats' in your Profile first.",
                                ),
                              ),
                            );
                          }
                          return;
                        }

                        // 0. Check Capacity Limit
                        var activeSnap = await FirebaseFirestore.instance
                            .collection("rideRequests")
                            .where(
                              "driver_id",
                              isEqualTo: FirebaseAuth.instance.currentUser!.uid,
                            )
                            .where(
                              "status",
                              whereIn: ["accepted", "arrived", "ontrip"],
                            )
                            .get();

                        int currentActive = activeSnap.docs.length;

                        if (currentActive >= seatCapacity) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.red,
                                content: Text(
                                  "Vehicle Full! You have $currentActive active rides. Capacity: $seatCapacity.",
                                ),
                              ),
                            );
                          }
                          return;
                        }

                        // 1. Update rideRequest
                        FirebaseFirestore.instance
                            .collection("rideRequests")
                            .doc(rideRequestId)
                            .update({
                              "status": "accepted",
                              "driver_id":
                                  FirebaseAuth.instance.currentUser!.uid,
                              "driver_name": driverName,
                              "driver_phone": driverPhone,
                              "driver_college": driverCollege,
                            });

                        // --- SHADOW BOOKING UPDATE (Notification) ---
                        FirebaseFirestore.instance
                            .collection("bookings")
                            .where("rideRequestId", isEqualTo: rideRequestId)
                            .where("is_live_shadow", isEqualTo: true)
                            .get()
                            .then((docs) {
                              if (docs.docs.isNotEmpty) {
                                docs.docs.first.reference.update({
                                  "status": "accepted",
                                  "driverId":
                                      FirebaseAuth.instance.currentUser!.uid,
                                  "driverName": driverName,
                                  "driverPhone": driverPhone,
                                  "driverCollege": driverCollege,
                                });
                              }
                            });
                        // --------------------------------------------

                        // 2. Update status to idle (to receive next request?)
                        // If we want to pool, we MUST set to IDLE so the backend knows we are "Free" to take another
                        // (assuming backend only checks "idle" flag to send filtered requests)
                        FirebaseFirestore.instance
                            .collection("online_drivers")
                            .doc(FirebaseAuth.instance.currentUser!.uid)
                            .update({"newRideStatus": "idle"});

                        // 3. Navigate (or show Snackbar)
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Ride Accepted! Go to Map."),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        "Accept",
                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationRow(IconData icon, Color iconColor, String text) {
    return Row(
      children: [
        Icon(icon, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: text == "Unknown Pickup"
                  ? Colors.red
                  : _secondaryTextColor, // Highlight if unknown
              fontSize: 15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder(
      stream: FirebaseFirestore.instance
          .collection("trips")
          .where("driverId", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .where("status", isEqualTo: "completed") // Only completed trips
          .orderBy("time", descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (snapshot.hasError) {
          // Index might be missing for composite query (driverId + status + time)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Error: ${snapshot.error}. \n\nCheck logs for Index Link.",
                style: GoogleFonts.poppins(color: _textColor, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.history_toggle_off,
                  size: 60,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  "No completed trips yet.",
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
            var tripData = snapshot.data!.docs[index].data();
            String pickup = tripData["pickupAddress"] ?? "Unknown";
            String destination = tripData["destinationAddress"] ?? "Unknown";
            String amount = tripData["paymentAmount"]?.toString() ?? "0";

            String date = "";
            if (tripData["time"] != null) {
              if (tripData["time"] is Timestamp) {
                date = DateFormat(
                  "dd MMM, yyyy - hh:mm a",
                ).format((tripData["time"] as Timestamp).toDate());
              } else {
                date = tripData["time"].toString();
              }
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          date,
                          style: GoogleFonts.poppins(
                            color: _secondaryTextColor,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          "₹$amount",
                          style: GoogleFonts.poppins(
                            color: _textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Simplified Location Column for brevity
                    _buildLocationRow(Icons.my_location, Colors.green, pickup),
                    const SizedBox(height: 8),
                    _buildLocationRow(
                      Icons.location_on,
                      Colors.red,
                      destination,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void showCounterOfferDialog(
    BuildContext context,
    String rideRequestId,
    int distanceMeters,
  ) {
    TextEditingController counterController = TextEditingController();
    // Ensure distanceMeters is at least 1 to avoid division by zero or weirdness, though 0 distance means 0 fare.
    double distKm = distanceMeters / 1000.0;
    double maxFare = distKm * 1.9;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Counter Offer"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Enforcing Limit: ₹1.9/km"),
            Text("Max allowed: ₹${maxFare.toStringAsFixed(2)}"),
            const SizedBox(height: 10),
            TextField(
              controller: counterController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Enter Amount",
                prefixText: "₹",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (counterController.text.isEmpty) return;

              double entered =
                  double.tryParse(counterController.text) ?? 999999;

              if (entered > maxFare) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      "Cannot exceed limit: ₹${maxFare.toStringAsFixed(2)}",
                    ),
                  ),
                );
                return;
              }

              // Update Firestore
              FirebaseFirestore.instance
                  .collection("rideRequests")
                  .doc(rideRequestId)
                  .update({"counter_offer": counterController.text});

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Counter Offer Sent! Waiting for User..."),
                ),
              );
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }
}
