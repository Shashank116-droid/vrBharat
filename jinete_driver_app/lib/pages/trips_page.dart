import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:jinete_driver_app/methods/common_methods.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
          driverPhone = (snap.data() as Map)["phone"] ?? "";
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
      length: 2,
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
              Tab(text: "Requests"),
              Tab(text: "History"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Requests
            _buildRequestsTab(),

            // Tab 2: History
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

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
            "No Pending Requests",
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
