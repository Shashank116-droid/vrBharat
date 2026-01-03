import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';

import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:jinete_driver_app/pages/chat_screen.dart';
import 'package:jinete_driver_app/global/global_var.dart';
import 'package:jinete_driver_app/methods/common_methods.dart';
import 'package:jinete_driver_app/push_notification/push_notification_system.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final Completer<GoogleMapController> googleMapCompleterController =
      Completer<GoogleMapController>();
  GoogleMapController? controllerGoogleMap;
  Position? currentPositionOfUser;

  // Driver Status
  bool isDriverActive = true;
  String driverName = "";
  String driverPhone = "";
  String verificationStatus = "pending";

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

  // Persistent bar height
  double bottomSheetHeight = 220;

  @override
  void initState() {
    super.initState();
    PushNotificationSystem.initializeNotification();
    getUserInfo();
  }

  @override
  void dispose() {
    activeTripSubscription?.cancel();
    rideRequestSubscription?.cancel();
    positionStreamHomePage?.cancel();
    super.dispose();
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
              verificationStatus =
                  (docSnapshot.data() as Map)["verificationStatus"] ??
                  "pending";
            });

            if (verificationStatus == "approved") {
              // If approved, trigger online status (if map ready)
              // We can check if controller is ready or just call it,
              // but safer to wait for map or if map is already ready.
              if (controllerGoogleMap != null) {
                driverIsOnlineNow();
              }
            }
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

    // Initial check
    driverIsOnlineNow();
  }

  StreamSubscription? rideRequestSubscription;
  StreamSubscription? activeTripSubscription;
  final geo = GeoFlutterFire();

  driverIsOnlineNow() async {
    // SECURITY CHECK: Verify Status
    if (verificationStatus != "approved") {
      return;
    }

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
    activeTripSubscription = FirebaseFirestore.instance
        .collection("rideRequests")
        .where("driver_id", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .snapshots()
        .listen((event) {
          if (event.docs.isNotEmpty) {
            QueryDocumentSnapshot? doc;

            // 1. Prioritize Active Trips
            var activeDocs = event.docs.where((d) {
              return ["accepted", "arrived", "ontrip"].contains(d["status"]);
            }).toList();

            if (activeDocs.isNotEmpty) {
              doc = activeDocs[0];
            } else if (activeRideRequestId.isNotEmpty) {
              // 2. Only Check for Cancelled if we are currently tracking a ride
              var currentRideDocs = event.docs
                  .where(
                    (d) =>
                        d.id == activeRideRequestId &&
                        d["status"] == "cancelled",
                  )
                  .toList();
              if (currentRideDocs.isNotEmpty) {
                doc = currentRideDocs[0];
              }
            }

            if (doc != null) {
              // Extract Coordinates
              LatLng? pLatLng;
              LatLng? dLatLng;
              try {
                if (doc.data().toString().contains("pickup") &&
                    (doc["pickup"] is Map)) {
                  var p = doc["pickup"];
                  pLatLng = LatLng(
                    double.parse(p["latitude"].toString()),
                    double.parse(p["longitude"].toString()),
                  );
                }
                if (doc.data().toString().contains("dropoff") &&
                    (doc["dropoff"] is Map)) {
                  var d = doc["dropoff"];
                  dLatLng = LatLng(
                    double.parse(d["latitude"].toString()),
                    double.parse(d["longitude"].toString()),
                  );
                }
              } catch (e) {
                // print("Error parsing coords: $e");
              }

              // Route Logic
              bool activeTripRequestCanceled = (doc["status"] == "cancelled");
              String newRideStatus = doc["status"];

              if (!activeTripRequestCanceled &&
                  pLatLng != null &&
                  dLatLng != null) {
                if (activeRideRequestId != doc.id ||
                    activeRideStatus != newRideStatus) {
                  LatLng? originLat;
                  LatLng? destinationLat;
                  String? originTitle;
                  String? destinationTitle;

                  if (newRideStatus == "accepted" ||
                      newRideStatus == "arrived") {
                    if (currentPositionOfUser != null) {
                      originLat = LatLng(
                        currentPositionOfUser!.latitude,
                        currentPositionOfUser!.longitude,
                      );
                      destinationLat = pLatLng;
                      originTitle = "My Location";
                      destinationTitle = "Pickup Location";
                    }
                  } else if (newRideStatus == "ontrip") {
                    originLat = pLatLng;
                    destinationLat = dLatLng;
                    originTitle = "Pickup Location";
                    destinationTitle = "Dropoff Location";
                  }

                  if (originLat != null && destinationLat != null) {
                    retrieveDirectionDetails(
                      originLat,
                      destinationLat,
                      originTitle!,
                      destinationTitle!,
                    );
                  }
                }
              }

              setState(() {
                activeRideRequestId = doc!.id;
                activeRideStatus = doc["status"];
                activeRideOtp = (doc.data() as Map).containsKey("otp")
                    ? (doc["otp"] ?? "")
                    : "";
                pickupLatLng = pLatLng;
                dropoffLatLng = dLatLng;

                riderName = (doc.data() as Map).containsKey("rider_name")
                    ? doc["rider_name"]
                    : "Rider";
                riderPhone = (doc.data() as Map).containsKey("rider_phone")
                    ? doc["rider_phone"]
                    : "";
                riderCollege =
                    ((doc.data() as Map).containsKey("rider_college") &&
                        doc["rider_college"] != null)
                    ? doc["rider_college"]
                    : "College Info Unavailable";
                pickupAddress =
                    (doc.data() as Map).containsKey("pickup_address")
                    ? doc["pickup_address"]
                    : "";
                dropOffAddress =
                    (doc.data() as Map).containsKey("dropoff_address")
                    ? doc["dropoff_address"]
                    : "";

                bottomSheetHeight = 320;
              });

              if (doc["status"] == "cancelled") {
                String cancelledBy =
                    (doc.data() as Map).containsKey("cancelled_by")
                    ? doc["cancelled_by"]
                    : "";

                if (cancelledBy == "rider") {
                  PushNotificationSystem.showNotification(
                    "Trip Cancelled",
                    "The Passenger has cancelled the trip.",
                  );
                  if (context.mounted) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext c) => AlertDialog(
                        title: const Text("Trip Cancelled"),
                        content: const Text(
                          "The Passenger has cancelled the trip.",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(c);
                            },
                            child: const Text("OK"),
                          ),
                        ],
                      ),
                    );
                  }
                }
                _resetToIdle();
              }
            } else {
              _resetToIdle();
            }
          } else {
            _resetToIdle();
          }
        });
  }

  void _resetToIdle() {
    setState(() {
      activeRideRequestId = "";
      activeRideStatus = "idle";
      bottomSheetHeight = 120;
      polylineSet.clear();
      markersSet.clear();
      circlesSet.clear();
      pLineCoOrdinatesList.clear();
    });
  }

  retrieveDirectionDetails(
    LatLng originLatLng,
    LatLng destinationLatLng,
    String originTitle,
    String destinationTitle,
  ) async {
    var details = await CommonMethods.getDirectionDetails(
      originLatLng,
      destinationLatLng,
    );

    if (details == null) return;

    setState(() {
      tripDirectionDetails = details;
    });

    List<PointLatLng> decodedPolylinePointsResult = PolylinePoints()
        .decodePolyline(tripDirectionDetails!.encodedPoints!);

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

      Marker originMarker = Marker(
        markerId: const MarkerId("originID"),
        position: originLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: InfoWindow(title: originTitle, snippet: "Origin"),
      );

      Marker destinationMarker = Marker(
        markerId: const MarkerId("destinationID"),
        position: destinationLatLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: destinationTitle, snippet: "Destination"),
      );

      markersSet.add(originMarker);
      markersSet.add(destinationMarker);

      Circle originCircle = Circle(
        circleId: const CircleId("originID"),
        strokeColor: Colors.yellow,
        strokeWidth: 4,
        radius: 12,
        center: originLatLng,
        fillColor: Colors.yellowAccent,
      );

      Circle destinationCircle = Circle(
        circleId: const CircleId("destinationID"),
        strokeColor: Colors.orange,
        strokeWidth: 4,
        radius: 12,
        center: destinationLatLng,
        fillColor: Colors.orangeAccent,
      );

      circlesSet.add(originCircle);
      circlesSet.add(destinationCircle);
    });

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
    super.build(context);
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
            padding: const EdgeInsets.only(bottom: 240),
            onMapCreated: (GoogleMapController mapController) {
              controllerGoogleMap = mapController;
              updateMapTheme(controllerGoogleMap!);
              googleMapCompleterController.complete(controllerGoogleMap);

              getCurrentLiveLocationOfDriver();
            },
            onTap: (LatLng latLng) {},
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
                  top: Radius.circular(25),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 18,
                    spreadRadius: 2,
                    offset: Offset(0, -5),
                  ),
                ],
                border: const Border(
                  top: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- VERIFICATION PENDING STATE ---
                      if (verificationStatus != "approved") ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.admin_panel_settings_outlined,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "Verification Pending",
                              style: GoogleFonts.poppins(
                                color: Colors.orangeAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(
                          color: Colors.orange,
                          backgroundColor: Colors.white10,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Your documents are under review. You cannot accept rides until verified by Admin.",
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ] else ...[
                        // --- IDLE STATE ---
                        if (activeRideStatus == "idle" ||
                            activeRideStatus == "") ...[
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                color: Colors.white60,
                              ),
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

                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Colors.white10,
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (c) => ChatScreen(
                                            rideRequestId: activeRideRequestId,
                                            otherUserName: riderName,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.chat_bubble,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.orange.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
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
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    onPressed: () {
                                      if (riderPhone.isNotEmpty) {
                                        launchUrl(
                                          Uri.parse("tel://$riderPhone"),
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.phone,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
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
                                  showOtpDialog();
                                } else if (activeRideStatus == "ontrip") {
                                  FirebaseFirestore.instance
                                      .collection("rideRequests")
                                      .doc(activeRideRequestId)
                                      .update({"status": "ended"});
                                  showPaymentDialog(activeRideRequestId);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: activeRideStatus == "ontrip"
                                    ? Colors.redAccent
                                    : (activeRideStatus == "accepted"
                                          ? Colors.orange
                                          : Colors.green),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                elevation: 8,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
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
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text("No"),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                              FirebaseFirestore.instance
                                                  .collection("rideRequests")
                                                  .doc(activeRideRequestId)
                                                  .update({
                                                    "status": "cancelled",
                                                    "cancelled_by": "driver",
                                                  });
                                            },
                                            child: const Text(
                                              "Yes",
                                              style: TextStyle(
                                                color: Colors.red,
                                              ),
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
                    ],
                  ),
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

  void showPaymentDialog(String requestId) {
    FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(requestId)
        .get()
        .then((snap) {
          if (!snap.exists) return;
          String fare = (snap.data() as Map)["fare_offer"]?.toString() ?? "0";

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Center(child: Text("Collect Payment")),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Total Amount",
                    style: GoogleFonts.poppins(color: Colors.grey),
                  ),
                  Text(
                    "₹$fare",
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text("Select Payment Method:"),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (c) => AlertDialog(
                                title: const Text("Cash Payment"),
                                content: const Text(
                                  "Please collect the cash from the passenger.",
                                ),
                                actions: [
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(c);
                                      endTrip(requestId, fare);
                                    },
                                    child: const Text("Collected"),
                                  ),
                                ],
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          child: const Text("CASH"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (c) => AlertDialog(
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "Scan to Pay ₹$fare",
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 200,
                                      width: 200,
                                      child: QrImageView(
                                        data:
                                            "upi://pay?pa=driver@upi&pn=JineteDriver&am=$fare&cu=INR", // Mock UPI
                                        version: QrVersions.auto,
                                        size: 200.0,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(c);
                                        endTrip(requestId, fare);
                                      },
                                      child: const Text("Payment Received"),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                          ),
                          child: const Text("UPI"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
  }

  void endTrip(String requestId, String fare) {
    FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(requestId)
        .get()
        .then((snap) {
          if (snap.exists) {
            var data = snap.data() as Map;

            // 1. Create Trip Record
            Map<String, dynamic> tripHistoryMap = {
              "driverId": FirebaseAuth.instance.currentUser!.uid,
              "riderId": data["rider_id"] ?? "",
              "paymentAmount": fare,
              "time": FieldValue.serverTimestamp(),
              "status": "completed",
              "pickupAddress": data["pickup_address"] ?? "",
              "destinationAddress": data["dropoff_address"] ?? "",
            };

            FirebaseFirestore.instance.collection("trips").add(tripHistoryMap);

            // 2. Mark Request as Ended
            FirebaseFirestore.instance
                .collection("rideRequests")
                .doc(requestId)
                .update({"status": "ended"});

            // 3. Reset Driver
            FirebaseFirestore.instance
                .collection("online_drivers")
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .update({"newRideStatus": "idle"});
          }
        });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Trip Completed Successfully!")),
    );
  }
}
