import 'dart:convert';
import 'dart:async'; // Added for StreamSubscription
// import 'dart:typed_data'; // Unnecessary

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';

import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:jinete_driver_app/global/global_var.dart';
import 'package:jinete_driver_app/methods/common_methods.dart';
import 'package:jinete_driver_app/push_notification/push_notification_system.dart';

import 'package:url_launcher/url_launcher.dart';

// import '../widgets/custom_drawer.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Completer<GoogleMapController> googleMapCompleterController =
      Completer<GoogleMapController>();
  GoogleMapController? controllerGoogleMap;
  Position? currentPositionOfUser;

  // Driver Status
  bool isDriverActive = true;
  String driverName = "";
  String driverPhone = "";

  StreamSubscription<Position>? positionStreamHomePage;

  Set<Marker> markersSet = {};
  Set<Circle> circlesSet = {};
  Set<Polyline> polylineSet = {};
  List<LatLng> pLineCoOrdinatesList = [];
  DirectionDetails? tripDirectionDetails;

  String activeRideRequestId = ""; // Track active ride ID
  String activeRideStatus = ""; // accepted, arrived, ontrip
  String activeRideOtp = ""; // Store for verification

  // Rider Details
  String riderName = "Rider";
  String riderPhone = "";
  String riderCollege = "";
  String pickupAddress = "";
  String dropOffAddress = "";
  LatLng? pickupLatLng;
  LatLng? dropoffLatLng;

  // UI Logic: tripPanelHeight is now effectively always visible (different states)
  // We will control content visibility instead of height generally, OR use height to animate hidden/shown.
  // User wants a PERSISTENT bar "Waiting for rides".
  double bottomSheetHeight = 220;

  @override
  void initState() {
    super.initState();
    getUserInfo();
  }

  void getUserInfo() {
    FirebaseFirestore.instance
        .collection("drivers")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get()
        .then((docSnapshot) {
          if (docSnapshot.exists) {
            setState(() {
              driverName = (docSnapshot.data() as Map)["name"];
              driverPhone = (docSnapshot.data() as Map)["phone"];
            });
          }
        });
  }

  void updateMapTheme(GoogleMapController controller) {
    getJsonFileFromThemes(
      "themes/aubergine_style.json",
    ).then((value) => setGoogleMapStyle(value, controller));
  }

  Future<String> getJsonFileFromThemes(String mapStylePath) async {
    ByteData byteData = await rootBundle.load(mapStylePath);
    var list = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return utf8.decode(list);
  }

  setGoogleMapStyle(String googleMapStyle, GoogleMapController controller) {
    controller.setMapStyle(googleMapStyle);
  }

  getCurrentLiveLocationOfDriver() async {
    Position positionOfUser = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
    currentPositionOfUser = positionOfUser;

    LatLng positionOfUserInLatLng = LatLng(
      currentPositionOfUser!.latitude,
      currentPositionOfUser!.longitude,
    );

    CameraPosition cameraPosition = CameraPosition(
      target: positionOfUserInLatLng,
      zoom: 15,
    );
    controllerGoogleMap!.animateCamera(
      CameraUpdate.newCameraPosition(cameraPosition),
    );

    // Auto-Online when map is ready and location is found
    driverIsOnlineNow();
  }

  StreamSubscription? rideRequestSubscription;
  final geo = GeoFlutterFire();

  driverIsOnlineNow() async {
    // 1. Get current position
    Position pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    currentPositionOfUser = pos;

    // 2. Set location in Firestore (online_drivers)
    GeoFirePoint myLocation = geo.point(
      latitude: currentPositionOfUser!.latitude,
      longitude: currentPositionOfUser!.longitude,
    );
    FirebaseFirestore.instance
        .collection("online_drivers")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .set({
          "position": myLocation.data,
          "name": driverName,
          "phone": driverPhone,
          "newRideStatus": "idle",
        });

    // 4. Start listening to live updates
    driverLocationRealtimeUpdates();

    // 5. Start listening for new ride requests
    rideRequestSubscription = PushNotificationSystem.listenForNewRide(context);

    // 6. Check for Active Trip
    checkActiveTrip();
  }

  void checkActiveTrip() {
    FirebaseFirestore.instance
        .collection("rideRequests")
        .where("driver_id", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where("status", whereIn: ["accepted", "arrived", "ontrip"])
        .snapshots()
        .listen((event) {
          if (event.docs.isNotEmpty) {
            var doc = event.docs[0];

            // Extract coordinates
            LatLng? pLatLng;
            LatLng? dLatLng;

            try {
              if (doc.data().containsKey("pickup")) {
                var p = doc["pickup"];
                pLatLng = LatLng(
                  double.parse(p["latitude"].toString()),
                  double.parse(p["longitude"].toString()),
                );
              }
              if (doc.data().containsKey("dropoff")) {
                var d = doc["dropoff"];
                dLatLng = LatLng(
                  double.parse(d["latitude"].toString()),
                  double.parse(d["longitude"].toString()),
                );
              }
            } catch (e) {
              print("Error parsing coordinates: $e");
            }

            // Draw route if not already drawn or if request changed
            // Draw route if not already drawn or if request changed
            if (activeRideRequestId != doc.id &&
                pLatLng != null &&
                dLatLng != null) {
              // New ride detected, fetch route
              retrieveDirectionDetails(pLatLng, dLatLng);
            }

            setState(() {
              activeRideRequestId = doc.id;
              activeRideStatus = doc["status"];
              activeRideOtp = doc.data().containsKey("otp")
                  ? (doc["otp"] ?? "")
                  : "";
              pickupLatLng = pLatLng;
              dropoffLatLng = dLatLng;

              riderName = doc.data().containsKey("rider_name")
                  ? doc["rider_name"]
                  : "Rider";
              riderPhone = doc.data().containsKey("rider_phone")
                  ? doc["rider_phone"]
                  : "";
              riderCollege =
                  (doc.data().containsKey("rider_college") &&
                      doc["rider_college"] != null &&
                      doc["rider_college"].toString().isNotEmpty)
                  ? doc["rider_college"]
                  : "College Info Unavailable";
              pickupAddress = doc.data().containsKey("pickup_address")
                  ? doc["pickup_address"]
                  : "";
              dropOffAddress = doc.data().containsKey("dropoff_address")
                  ? doc["dropoff_address"]
                  : "";

              bottomSheetHeight = 320; // Expand for Trip Details
            });
          } else {
            setState(() {
              activeRideRequestId = "";
              activeRideStatus = "idle";
              bottomSheetHeight = 120; // Low height for "Waiting"
              polylineSet.clear();
              markersSet.clear();
              circlesSet.clear();
              pLineCoOrdinatesList.clear();
            });
          }
        });
  }

  retrieveDirectionDetails(
    LatLng originLatLng,
    LatLng destinationLatLng,
  ) async {
    var details = await CommonMethods.getDirectionDetails(
      originLatLng,
      destinationLatLng,
    );

    if (details == null) return;

    setState(() {
      tripDirectionDetails = details;
    });

    List<PointLatLng> decodedPolylinePointsResult =
        PolylinePoints.decodePolyline(tripDirectionDetails!.encodedPoints!);

    pLineCoOrdinatesList.clear();

    if (decodedPolylinePointsResult.isNotEmpty) {
      for (PointLatLng pointLatLng in decodedPolylinePointsResult) {
        pLineCoOrdinatesList.add(
          LatLng(pointLatLng.latitude, pointLatLng.longitude),
        );
      }
    }

    polylineSet.clear();

    setState(() {
      Polyline polyline = Polyline(
        polylineId: const PolylineId("polylineID"),
        color: Colors.blueAccent,
        jointType: JointType.round,
        points: pLineCoOrdinatesList,
        width: 5,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
      );

      polylineSet.add(polyline);

      Marker pickUpMarker = Marker(
        markerId: const MarkerId("pickUpID"),
        position: originLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(
          title: "Pickup Location",
          snippet: "Client Location",
        ),
      );

      Marker dropOffMarker = Marker(
        markerId: const MarkerId("dropOffID"),
        position: destinationLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(
          title: "Dropoff Location",
          snippet: "Destination",
        ),
      );

      markersSet.add(pickUpMarker);
      markersSet.add(dropOffMarker);

      Circle pickUpCircle = Circle(
        circleId: const CircleId("pickUpID"),
        strokeColor: Colors.orange,
        strokeWidth: 4,
        radius: 12,
        center: originLatLng,
        fillColor: Colors.orangeAccent,
      );

      Circle dropOffCircle = Circle(
        circleId: const CircleId("dropOffID"),
        strokeColor: Colors.green,
        strokeWidth: 4,
        radius: 12,
        center: destinationLatLng,
        fillColor: Colors.greenAccent,
      );

      circlesSet.add(pickUpCircle);
      circlesSet.add(dropOffCircle);
    });

    // Fit map to bounds
    LatLngBounds bounds;
    if (originLatLng.latitude > destinationLatLng.latitude &&
        originLatLng.longitude > destinationLatLng.longitude) {
      bounds = LatLngBounds(
        southwest: destinationLatLng,
        northeast: originLatLng,
      );
    } else if (originLatLng.longitude > destinationLatLng.longitude) {
      bounds = LatLngBounds(
        southwest: LatLng(originLatLng.latitude, destinationLatLng.longitude),
        northeast: LatLng(destinationLatLng.latitude, originLatLng.longitude),
      );
    } else if (originLatLng.latitude > destinationLatLng.latitude) {
      bounds = LatLngBounds(
        southwest: LatLng(destinationLatLng.latitude, originLatLng.longitude),
        northeast: LatLng(originLatLng.latitude, destinationLatLng.longitude),
      );
    } else {
      bounds = LatLngBounds(
        southwest: originLatLng,
        northeast: destinationLatLng,
      );
    }

    controllerGoogleMap!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 70),
    );
  }

  void driverLocationRealtimeUpdates() {
    positionStreamHomePage = Geolocator.getPositionStream().listen((
      Position position,
    ) {
      currentPositionOfUser = position;

      if (isDriverActive == true) {
        GeoFirePoint myLocation = geo.point(
          latitude: currentPositionOfUser!.latitude,
          longitude: currentPositionOfUser!.longitude,
        );
        FirebaseFirestore.instance
            .collection("online_drivers")
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .update({"position": myLocation.data});
      }

      LatLng latLng = LatLng(
        currentPositionOfUser!.latitude,
        currentPositionOfUser!.longitude,
      );

      Marker driverMarker = Marker(
        markerId: const MarkerId("currentLocation"),
        position: latLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        infoWindow: const InfoWindow(title: "My Location"),
      );

      setState(() {
        markersSet.removeWhere(
          (marker) => marker.markerId.value == "currentLocation",
        );
        markersSet.add(driverMarker);
      });

      controllerGoogleMap!.animateCamera(CameraUpdate.newLatLng(latLng));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            myLocationEnabled: true,
            initialCameraPosition: googlePlexInitialPosition,

            polylines: polylineSet,
            markers: markersSet,
            circles: circlesSet,
            padding: const EdgeInsets.only(bottom: 240), // Adjust for panel
            onMapCreated: (GoogleMapController mapController) {
              controllerGoogleMap = mapController;
              updateMapTheme(controllerGoogleMap!);
              googleMapCompleterController.complete(controllerGoogleMap);

              getCurrentLiveLocationOfDriver();
            },
            onTap: (LatLng latLng) {
              // Route selection removed
            },
          ),

          // Persistent Bottom Panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: bottomSheetHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF181820),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 10,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- IDLE STATE ---
                    if (activeRideStatus == "idle" ||
                        activeRideStatus == "") ...[
                      Row(
                        children: [
                          const Icon(Icons.access_time, color: Colors.white60),
                          const SizedBox(width: 12),
                          Text(
                            "Waiting for Rides...",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(
                        color: Colors.green,
                        backgroundColor: Colors.white10,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Please stay online to receive trip requests.",
                        style: GoogleFonts.poppins(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    // --- TRIP STATE ---
                    if (activeRideStatus != "idle" &&
                        activeRideStatus != "") ...[
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            activeRideStatus == "ontrip"
                                ? "Heading to Destination"
                                : "Picking Up Rider",
                            style: GoogleFonts.poppins(
                              color: Colors.greenAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              activeRideStatus.toUpperCase(),
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Rider Info Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.white10,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    riderName,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    riderPhone,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    riderCollege,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Navigation Button
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.blueAccent,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () {
                                  double lat;
                                  double lng;

                                  if (activeRideStatus == "ontrip" &&
                                      dropoffLatLng != null) {
                                    lat = dropoffLatLng!.latitude;
                                    lng = dropoffLatLng!.longitude;
                                  } else if (pickupLatLng != null) {
                                    lat = pickupLatLng!.latitude;
                                    lng = pickupLatLng!.longitude;
                                  } else {
                                    return;
                                  }

                                  String googleMapUrl =
                                      "google.navigation:q=$lat,$lng&mode=d";

                                  print(
                                    "DEBUG: Launching Google Maps Navigation: $googleMapUrl",
                                  );

                                  launchUrl(
                                    Uri.parse(googleMapUrl),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                                icon: const Icon(
                                  Icons.map,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Call Button
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: () {
                                  if (riderPhone.isNotEmpty) {
                                    launchUrl(Uri.parse("tel://$riderPhone"));
                                  }
                                },
                                icon: const Icon(
                                  Icons.phone,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Show OTP button if arrived but not verified
                            if (activeRideStatus == "arrived")
                              ElevatedButton(
                                onPressed: () => showOtpDialog(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(12),
                                ),
                                child: const Icon(
                                  Icons.vpn_key,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Action Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (activeRideStatus == "accepted") {
                              FirebaseFirestore.instance
                                  .collection("rideRequests")
                                  .doc(activeRideRequestId)
                                  .update({"status": "arrived"});
                            } else if (activeRideStatus == "arrived") {
                              // Also allow tapping main button to verify
                              showOtpDialog();
                            } else if (activeRideStatus == "ontrip") {
                              FirebaseFirestore.instance
                                  .collection("rideRequests")
                                  .doc(activeRideRequestId)
                                  .update({"status": "completed"});
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: activeRideStatus == "ontrip"
                                ? Colors.redAccent
                                : (activeRideStatus == "accepted"
                                      ? Colors.orange
                                      : Colors.green),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            activeRideStatus == "accepted"
                                ? "Arrived at Pickup"
                                : (activeRideStatus == "arrived"
                                      ? "Enter OTP to Start"
                                      : "End Trip"),
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                      if (activeRideStatus == "accepted" ||
                          activeRideStatus == "arrived")
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Center(
                            child: TextButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("Cancel Trip"),
                                    content: const Text(
                                      "Are you sure you want to cancel this trip?",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text("No"),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                          FirebaseFirestore.instance
                                              .collection("rideRequests")
                                              .doc(activeRideRequestId)
                                              .update({"status": "cancelled"});
                                        },
                                        child: const Text(
                                          "Yes",
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: Text(
                                "Cancel Trip",
                                style: GoogleFonts.poppins(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: null,
    );
  }

  void showOtpDialog() {
    TextEditingController otpController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enter OTP"),
        content: TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: "4-Digit Code"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (otpController.text.trim() == activeRideOtp) {
                FirebaseFirestore.instance
                    .collection("rideRequests")
                    .doc(activeRideRequestId)
                    .update({"status": "ontrip"});
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("OTP Verified! Trip Started.")),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Invalid OTP! Ask User."),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Verify"),
          ),
        ],
      ),
    );
  }
}
