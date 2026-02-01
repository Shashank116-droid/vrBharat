import "dart:math";
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import "dart:async";
import "dart:convert";
import "dart:typed_data";
import 'package:geoflutterfire2/geoflutterfire2.dart';
import "package:firebase_auth/firebase_auth.dart";
// FCM import removed
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "package:geolocator/geolocator.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:jinete/authentication/login_screen.dart";
import 'package:jinete/pages/chat_screen.dart'; // Added
import 'package:share_plus/share_plus.dart';
import "package:jinete/global/global_var.dart";
import "package:jinete/methods/common_methods.dart";
import "package:jinete/pages/search_destination_page.dart";
import "package:flutter_polyline_points/flutter_polyline_points.dart";
import "package:jinete/models/direction_details.dart";
import "package:url_launcher/url_launcher.dart";
// PushNotificationService import removed
import "package:jinete/pages/dashboard.dart";

class HomePage extends StatefulWidget {
  final String? autoStartRideId;
  const HomePage({super.key, this.autoStartRideId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Completer<GoogleMapController> googleMapCompleterController =
      Completer<GoogleMapController>();
  GoogleMapController? controllerGoogleMap;

  Position? currentPositionOfUser;
  GlobalKey<ScaffoldState> sKey = GlobalKey<ScaffoldState>();
  CommonMethods cMethods = CommonMethods();
  double searchContainerHeight = 220;
  double tripDetailsContainerHeight = 0; // Starts hidden
  double driverDetailsContainerHeight = 0; // Starts hidden

  // Verification Status
  String verificationStatus = "pending";
  bool hasPriorRejection = false; // Starts hidden
  double bottomMapPadding = 0;

  String rideOtp = "";
  bool isTripStarted = false;
  String driverName = "Driver";
  String driverPhone = "";
  String driverCollege = "";
  String rideStatusText = "Driver Arriving";

  String userCollege = ""; // For sending to driver
  StreamSubscription<DocumentSnapshot>? driverLocationSubscription;
  StreamSubscription<DocumentSnapshot>? rideStreamSubscription;
  StreamSubscription? bookingStreamSubscription; // Added for cleanup
  bool drawerOpen = true;
  BitmapDescriptor? carMarkerIcon;

  DirectionDetails? tripDirectionDetails;
  TextEditingController offerAmountTextEditingController =
      TextEditingController();
  TextEditingController pickUpTextEditingController = TextEditingController();

  List<LatLng> pLineCoOrdinatesList = [];
  Set<Polyline> polylineSet = {};

  Set<Marker> markersSet = {};
  Set<Circle> circlesSet = {};

  String currentRideRequestId = ""; // Track active request
  String userCurrentAddress = "Current Location"; // Default fallback
  String dropOffAddress = "Destination"; // Stores destination name
  DateTime? scheduledTripDate; // Advance Booking
  List<Map<String, dynamic>> scheduledDriversList = [];

  // Design Colors
  final Color _cardColor = const Color(0xFF181820);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;

  @override
  void initState() {
    super.initState();
    getUserInfo();
    setupRideListeners();
  }

  @override
  void dispose() {
    rideStreamSubscription?.cancel();
    driverLocationSubscription?.cancel();
    bookingStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> setupRideListeners() async {
    if (widget.autoStartRideId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        initializeLiveRide(widget.autoStartRideId!);
      });
    }

    // Watch for Scheduled -> Started transition (Robust Fallback)
    print(
        "DEBUG: Setting up Booking Listener for ${FirebaseAuth.instance.currentUser?.uid}");
    bookingStreamSubscription = FirebaseFirestore.instance
        .collection("bookings")
        .where("riderId", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where("status", isEqualTo: "started")
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        var data = snapshot.docs.first.data();
        print("DEBUG: Booking Listener Fired! Status: ${data['status']}");
        if (data["rideRequestId"] != null) {
          String rId = data["rideRequestId"];
          print("DEBUG: Ride Request ID from Booking: $rId");
          if (currentRideRequestId != rId || !isTripStarted) {
            print("DEBUG: Initializing Live Ride for $rId");
            initializeLiveRide(rId);
          } else {
            print("DEBUG: Already tracking this ride or trip started.");
          }
        } else {
          print("DEBUG: rideRequestId is NULL in booking.");
        }
      } else {
        print("DEBUG: Booking Listener Fired but NO DOCS found.");
      }
    }, onError: (e) => print("DEBUG: Booking Listener Error: $e"));

    // 5. Check for EXISTING Active Live Ride (App Restart Persistence)
    checkActiveLiveRide();
  }

  void checkActiveLiveRide() {
    FirebaseFirestore.instance
        .collection("rideRequests")
        .where("rider_id", isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where("status", whereIn: ["new", "accepted", "arrived", "ontrip"])
        .limit(1)
        .get()
        .then((snap) {
          if (!mounted) return;
          if (snap.docs.isNotEmpty) {
            // Found an active ride! Restore State.
            var doc = snap.docs.first;
            String status = doc["status"];
            String rideId = doc.id;

            print("DEBUG: Restoring Active Ride State: $rideId ($status)");

            // Restore Request ID
            currentRideRequestId = rideId;

            if (status == "new") {
              // Restore Searching Dialog
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  showSearchingForDriversDialog();
                  listenToRideStream(); // Re-attach listener
                }
              });
            } else {
              // Restore Live Ride UI (Banner, etc)
              initializeLiveRide(rideId);
            }
          }
        });
  }

  void initializeLiveRide(String rideId) {
    print("DEBUG: initializeLiveRide CALLED with $rideId");
    currentRideRequestId = rideId;
    isTripStarted = true;
    setState(() {
      // Clear legacy UI
      searchContainerHeight = 0;
      tripDetailsContainerHeight = 0;
      driverDetailsContainerHeight = 380; // Show Driver Details
      bottomMapPadding = 280; // Ensure map padding (adjust if needed)
      drawerOpen = true; // Ensure drawer is accessible or handle properly
    });

    // Start Listening to the Ride
    // We assume saving request info triggers the listeners
    // But since this is a new ride request, we might need to manually trigger the subscription
    // Let's verify how saveRideRequestInformation works, or replicate it.

    // Direct Listener Implementation for Robustness:
    rideStreamSubscription = FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(rideId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        String status = "unknown";
        try {
          // Update Driver Location & Status
          var data = snapshot.data() as Map<String, dynamic>;

          // Update Driver Details
          setState(() {
            driverName = data["driver_name"] ?? driverName;
            driverPhone = data["driver_phone"] ?? driverPhone;
            driverCollege = data["driver_college"] ?? driverCollege;
            rideOtp = data["otp"] ?? rideOtp;
            print("DEBUG: User App initializeLiveRide - rideOtp: $rideOtp");
            print("DEBUG: isTripStarted: $isTripStarted");

            // Force Panel Open
            driverDetailsContainerHeight = 380;
            print("DEBUG: Setting driverDetailsContainerHeight to 280");
            bottomMapPadding = 300;
          });

          // Update Status text
          status = data['status'] ?? "unknown";

          // Trigger Notification
          if (status == 'arrived' && rideStatusText != 'Driver Arrived') {
            // Local notification removed
          }

          setState(() {
            rideStatusText = status == 'accepted'
                ? 'Driver Arriving'
                : status == 'arrived'
                    ? 'Driver Arrived'
                    : status == 'ontrip'
                        ? 'On Trip'
                        : 'Ride Started';
          });

          // Fetch Driver Location
          if (data['driver_id'] != null) {
            listenToDriverLocation(data['driver_id']);
          }
        } catch (e) {
          print("DEBUG: Error in Live Ride Listener: $e");
        }

        // Update UI based on status
        if (status == "ended") {
          // Shadow update removed

          // Get Fare
          String fare = "0";
          if (snapshot.data() != null) {
            fare = (snapshot.data() as Map)["fare_offer"]?.toString() ?? "0";
          }

          // Show Completed Dialog
          showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                    backgroundColor: _cardColor,
                    title: Text("Trip Completed",
                        style: GoogleFonts.poppins(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 60),
                        const SizedBox(height: 10),
                        Text("Hope you had a safe ride!",
                            style: GoogleFonts.poppins(color: Colors.white70)),
                        const SizedBox(height: 20),
                        Text("Total Fare",
                            style: GoogleFonts.poppins(
                                color: Colors.white54, fontSize: 12)),
                        Text("₹$fare",
                            style: GoogleFonts.poppins(
                                color: Colors.greenAccent,
                                fontSize: 32,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    actions: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor),
                        onPressed: () {
                          Navigator.pop(ctx); // Close Dialog
                          if (Navigator.canPop(context)) {
                            Navigator.pop(context); // Close Page
                          }
                          resetApp();
                        },
                        child: Text("Close",
                            style: GoogleFonts.poppins(color: Colors.white)),
                      )
                    ],
                  ));
          return;
        } else if (status == "cancelled") {
          // Shadow update removed

          String cancelledBy = snapshot.data()!["cancelled_by"] ?? "";

          if (cancelledBy == "rider") {
            // User cancelled - Silent Reset
            if (Navigator.canPop(context)) Navigator.pop(context);
            resetApp();
            return;
          }

          if (Navigator.canPop(context)) Navigator.pop(context);
          resetApp();
          // Local notification removed
          cMethods.displaySnackBar(
              "The Driver has Cancelled the Trip", context);
        }
      }
    });
  }

  driverLocationRealtimeUpdates(String driverId) {
    driverLocationSubscription = FirebaseFirestore.instance
        .collection("online_drivers")
        .doc(driverId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        var pos = data['position']['geopoint'];
        LatLng driverLatLng = LatLng(pos.latitude, pos.longitude);

        // Update Marker
        Marker driverMarker = Marker(
          markerId: MarkerId("driverMarker"),
          position: driverLatLng,
          icon: carMarkerIcon!,
        );

        setState(() {
          markersSet.add(driverMarker);
        });

        // Animate Camera?
        // controllerGoogleMap?.animateCamera(CameraUpdate.newLatLng(driverLatLng));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    createMarkerIcon();
  }

  getUserInfo() {
    FirebaseFirestore.instance
        .collection("users")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get()
        .then((snap) {
      if (snap.exists) {
        setState(() {
          userName =
              snap.data()?["fullName"] ?? snap.data()?["name"] ?? "Rider";
          userPhone =
              snap.data()?["phoneNumber"] ?? snap.data()?["phone"] ?? "";
          userCollege = snap.data()?["collegeName"] ?? "";
        });
      }
    });
  }

  void updateMapTheme(GoogleMapController controller) {
    getJsonFileFromThemes("themes/aubergine_style.json")
        .then((value) => setGoogleMapStyle(value, controller));
  }

  Future<String> getJsonFileFromThemes(String mapStylePath) async {
    ByteData byteData = await rootBundle.load(mapStylePath);
    var list = byteData.buffer
        .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    return utf8.decode(list);
  }

  setGoogleMapStyle(String googleMapStyle, GoogleMapController controller) {
    controller.setMapStyle(googleMapStyle);
  }

  retrieveDirectionDetails(DirectionDetails? directionDetails) async {
    if (directionDetails == null) return;
    // print("DEBUG: retrieveDirectionDetails called. Points: ${directionDetails.encodedPoints?.length}");

    List<PointLatLng> decodedPolylinePointsResult =
        PolylinePoints().decodePolyline(directionDetails.encodedPoints!);

    pLineCoOrdinatesList.clear();

    if (decodedPolylinePointsResult.isNotEmpty) {
      decodedPolylinePointsResult.forEach((PointLatLng pointLatLng) {
        pLineCoOrdinatesList
            .add(LatLng(pointLatLng.latitude, pointLatLng.longitude));
      });
    }

    polylineSet.clear();

    setState(() {
      // print("DEBUG: Updating UI with polyline. Coordinates: ${pLineCoOrdinatesList.length}");
      Polyline polyline = Polyline(
        polylineId: const PolylineId("polylineID"),
        color: _accentColor,
        jointType: JointType.round,
        points: pLineCoOrdinatesList,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        geodesic: true,
        width: 5,
      );

      polylineSet.add(polyline);
    });

    LatLngBounds bounds;
    LatLng startLatLng = pLineCoOrdinatesList.first;
    LatLng endLatLng = pLineCoOrdinatesList.last;

    if (startLatLng.latitude > endLatLng.latitude &&
        startLatLng.longitude > endLatLng.longitude) {
      bounds = LatLngBounds(southwest: endLatLng, northeast: startLatLng);
    } else if (startLatLng.longitude > endLatLng.longitude) {
      bounds = LatLngBounds(
          southwest: LatLng(startLatLng.latitude, endLatLng.longitude),
          northeast: LatLng(endLatLng.latitude, startLatLng.longitude));
    } else if (startLatLng.latitude > endLatLng.latitude) {
      bounds = LatLngBounds(
          southwest: LatLng(endLatLng.latitude, startLatLng.longitude),
          northeast: LatLng(startLatLng.latitude, endLatLng.longitude));
    } else {
      bounds = LatLngBounds(southwest: startLatLng, northeast: endLatLng);
    }

    controllerGoogleMap!
        .animateCamera(CameraUpdate.newLatLngBounds(bounds, 70));

    Marker pickUpMarker = Marker(
      markerId: const MarkerId("pickUpID"),
      position: startLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow:
          const InfoWindow(title: "My Location", snippet: "My Location"),
    );

    Marker dropOffMarker = Marker(
      markerId: const MarkerId("dropOffID"),
      position: endLatLng,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow:
          const InfoWindow(title: "Drop Off Location", snippet: "Destination"),
    );

    setState(() {
      markersSet.add(pickUpMarker);
      markersSet.add(dropOffMarker);
    });

    Circle pickUpCircle = Circle(
      circleId: const CircleId("pickUpID"),
      strokeColor: Colors.green,
      strokeWidth: 4,
      radius: 12,
      center: startLatLng,
      fillColor: Colors.greenAccent,
    );

    Circle dropOffCircle = Circle(
      circleId: const CircleId("dropOffID"),
      strokeColor: Colors.deepPurple,
      strokeWidth: 4,
      radius: 12,
      center: endLatLng,
      fillColor: Colors.deepPurpleAccent,
    );

    setState(() {
      circlesSet.add(pickUpCircle);
      circlesSet.add(dropOffCircle);

      // Update UI state
      searchContainerHeight = 0;
      tripDetailsContainerHeight = 400;
      bottomMapPadding = 360;

      // Pre-fill offer
      // Pre-fill offer
      tripDirectionDetails = directionDetails;
      double fare = CommonMethods.calculateFareAmount(directionDetails);
      offerAmountTextEditingController.text = fare.toString();
    });
  }

  // DatabaseReference? rideRequestRef; // Removed RTDB Ref
  List<String> availableDrivers = [];

  saveRideRequestInformation() async {
    if (scheduledTripDate != null) {
      createOpenBookingRequest();
      return;
    }

    if (pLineCoOrdinatesList.isEmpty) {
      cMethods.displaySnackBar(
          "Unable to get route. Please try again.", context);
      return;
    }

    var pickUpLocation = pLineCoOrdinatesList[0];
    var dropOffLocation = pLineCoOrdinatesList[pLineCoOrdinatesList.length - 1];

    Map<String, String> pickUpLocMap = {
      "latitude": pickUpLocation.latitude.toString(),
      "longitude": pickUpLocation.longitude.toString(),
    };

    Map<String, String> dropOffLocMap = {
      "latitude": dropOffLocation.latitude.toString(),
      "longitude": dropOffLocation.longitude.toString(),
    };

    // Generate OTP (4 digits)
    String otp = (1000 + Random().nextInt(9000)).toString();

    Map<String, dynamic> rideInfoMap = {
      "driver_id": "waiting",
      "payment_method": "cash",
      "pickup": pickUpLocMap,
      "dropoff": dropOffLocMap,
      "created_at": DateTime.now().toString(),
      "rider_name": userName.isEmpty ? "Rider" : userName,
      "rider_phone": userPhone,
      "rider_college": userCollege,
      "rider_id": FirebaseAuth.instance.currentUser!.uid,
      "otp": otp,

      "pickup_address": userCurrentAddress,
      "dropoff_address": dropOffAddress,
      "distance_value":
          tripDirectionDetails!.distanceValueDigits, // Added for limit calc
      "status": "new",
      "fare_offer": offerAmountTextEditingController.text,
      "counter_offer": "0", // Init counter offer
    };

    // 1. Save Request to Firestore
    // Using simple Map instead of rideRequestRef!.set(rideInfoMap)
    FirebaseFirestore.instance
        .collection("rideRequests")
        .add(rideInfoMap)
        .then((docRef) {
      currentRideRequestId = docRef.id; // Save ID

      // Shadow booking removed

      // 2. Search for Nearby Drivers, passing the new Firestore ID
      searchNearbyDrivers(docRef.id);

      // Show Searching Dialog
      showSearchingForDriversDialog();

      // Start listening for Ride Updates
      listenToRideStream();
    }).catchError((error) {
      if (!mounted) return;
      cMethods.displaySnackBar("Error: $error", context);
    });
  }

  void listenToRideStream() {
    if (currentRideRequestId.isEmpty) return;

    rideStreamSubscription = FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(currentRideRequestId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        if (!mounted) return;

        String status = snapshot.data()?["status"] ?? "";
        String counterOffer = snapshot.data()?["counter_offer"] ?? "0";
        String otp = snapshot.data()?["otp"] ?? "";

        // print("DEBUG: Ride Status Update: $status");

        // 1. Check for Acceptance
        if (status == "accepted") {
          // print("DEBUG: Driver Accepted");
          driverName = snapshot.data()?["driver_name"] ?? "Driver";
          driverPhone = snapshot.data()?["driver_phone"] ?? "";
          driverCollege =
              snapshot.data()?["driver_college"] ?? "College Info Unavailable";
          rideOtp = otp;

          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close "Searching..." Dialog
          }

          listenToDriverLocation(snapshot.data()?["driver_id"] ?? "");

          setState(() {
            searchContainerHeight = 0;
            tripDetailsContainerHeight = 0;
            driverDetailsContainerHeight = 380;
            bottomMapPadding = 320;
            rideStatusText = "Driver Arriving";
          });
        }
        // 2. Check for Driver Arrival
        else if (status == "arrived") {
          setState(() {
            rideStatusText = "Driver Arrived";
          });
          // Local notification removed
          cMethods.displaySnackBar(
              "Your ride has arrived, please share the OTP with your driver.",
              context);
        }
        // 3. Check for Trip Start
        else if (status == "ontrip") {
          setState(() {
            rideStatusText = "Heading to Destination";
            isTripStarted = true;
          });
        }
        // 4. Counter Offer
        else if (counterOffer != "0" &&
            counterOffer != offerAmountTextEditingController.text) {
          showCounterOfferDialog(counterOffer);
        }
        // 5. Check for Trip End
        else if (status == "ended" || status == "completed") {
          // print("DEBUG: Trip Ended. Showing Dialog.");

          // Stop listening immediately to prevent multiple triggers
          rideStreamSubscription?.cancel();
          rideStreamSubscription = null;

          showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                    title: const Text("Destination Reached"),
                    content: const Text(
                        "You have reached your destination, Now you can pay your Rider"),
                    actions: [
                      ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            resetApp(); // Reset UI only after user acknowledges
                          },
                          child: const Text("Pay & Rate"))
                    ],
                  ));
        }
        // 6. Check for Cancellation
        else if (status == "cancelled") {
          String cancelledBy = snapshot.data()?["cancelled_by"] ?? "";

          if (cancelledBy == "rider") {
            // User cancelled logic - Silent Reset
            rideStreamSubscription?.cancel();
            rideStreamSubscription = null;
            resetApp();
            if (Navigator.canPop(context) &&
                // Check if dialog is likely open (roughly)
                // Actually safer to just pop if we are in a dialog context,
                // but we might be on home screen.
                // Context usage here is tricky but standard for this codebase.
                true) {
              // We try to pop only if it's the Searching Dialog or similar.
              // Users might be on Home Page.
              // If we pop Home Page, app closes?
              // The Searching Dialog is a showDialog.
              // We should check if we are dealing with the Searching Dialog cancellation.
              // Line 678 checks 'Navigator.canPop'.
              // We'll leave it consistent with existing code but safe.
            }
            return;
          }

          if (cancelledBy == "driver") {
            // Local notification removed

            rideStreamSubscription?.cancel();
            rideStreamSubscription = null;
            resetApp();

            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext c) => AlertDialog(
                backgroundColor: const Color(0xFF181820),
                title: const Text("Ride Cancelled",
                    style: TextStyle(color: Colors.white)),
                content: const Text(
                    "The Driver has cancelled the Ride. Please request another Ride.",
                    style: TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child:
                        const Text("OK", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }
        }
      }
    });
  }

  void showCounterOfferDialog(String amount) {
    if (Navigator.canPop(context)) {
      // Close existing search container/flow if needed, or overlay.
      // For now, assume dialog is modal atop everything.
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
              title: const Text("New Fare Offer"),
              content: Text("Driver requested ₹$amount. Do you accept?"),
              actions: [
                TextButton(
                  onPressed: () {
                    // Reject - maybe cancel request or just keep waiting?
                    // For now: Just close, let driver decide to Accept original or leave.
                    Navigator.pop(context);
                    // Ideally, notify driver of Rejection:
                    // update counter_offer to "-1" or similar to signal rejection
                  },
                  child: const Text("No"),
                ),
                TextButton(
                  onPressed: () {
                    // Accept
                    FirebaseFirestore.instance
                        .collection("rideRequests")
                        .doc(currentRideRequestId)
                        .update({
                      "fare_offer": amount, // Update main fare
                      "counter_offer": "0", // Clear counter
                    });

                    setState(() {
                      offerAmountTextEditingController.text = amount;
                    });
                    Navigator.pop(context);
                    cMethods.displaySnackBar("Offer Accepted!", context);
                  },
                  child: const Text("Yes, Accept"),
                ),
              ],
            ));
  }

  void showSearchingForDriversDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            backgroundColor: _cardColor,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  CircularProgressIndicator(color: _accentColor),
                  const SizedBox(height: 20),
                  Text(
                    "Searching for Drivers...",
                    style: GoogleFonts.poppins(
                      color: _textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close dialog
                        // Ideally cancel the request in Firestore too
                        FirebaseFirestore.instance
                            .collection("rideRequests")
                            .doc(currentRideRequestId)
                            .update({
                          "status": "cancelled",
                          "cancelled_by": "rider",
                        });

                        // --- SHADOW BOOKING UPDATE (Notification) ---
                        FirebaseFirestore.instance
                            .collection("bookings")
                            .where("rideRequestId",
                                isEqualTo: currentRideRequestId)
                            .where("is_live_shadow", isEqualTo: true)
                            .get()
                            .then((docs) {
                          if (docs.docs.isNotEmpty) {
                            docs.docs.first.reference.update({
                              "status": "cancelled",
                              "cancelledBy": "rider",
                            });
                          }
                        });
                        // --------------------------------------------
                        cMethods.displaySnackBar("Request Cancelled", context);
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                      child: Text("Cancel",
                          style: GoogleFonts.poppins(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
  }

  void searchNearbyDrivers(String rideRequestId) {
    if (availableDrivers.isNotEmpty) {
      availableDrivers.clear();
    }

    if (scheduledTripDate == null) {
      // --- LIVE SEARCH (GEOFIRE) ---
      final geo = GeoFlutterFire();
      GeoFirePoint center = geo.point(
          latitude: pLineCoOrdinatesList[0].latitude,
          longitude: pLineCoOrdinatesList[0].longitude);

      var collectionReference =
          FirebaseFirestore.instance.collection('online_drivers');

      Stream<List<DocumentSnapshot>> stream = geo
          .collection(collectionRef: collectionReference)
          .within(center: center, radius: 20, field: 'position');

      stream.listen((List<DocumentSnapshot> documentList) {
        for (DocumentSnapshot doc in documentList) {
          // 1. Filter by Status
          String status =
              (doc.data() as Map)["newRideStatus"] ?? "waiting_input";
          if (status != "idle") continue;

          // 2. Hide Future Scheduled Drivers (Safety Check)
          var driverData = doc.data() as Map<String, dynamic>;
          if (driverData["tripDate"] != null) {
            DateTime dDate =
                DateTime.fromMillisecondsSinceEpoch(driverData["tripDate"]);
            if (dDate.isAfter(DateTime.now().add(const Duration(hours: 1))))
              continue;
          }

          _processDriverMatch(doc.id, driverData);
        }
        _checkNoDriversFound();
      });
    } else {
      // --- SCHEDULED OPEN BOOKING ---
      // User wants to broadcast request without selecting a specific driver
      createOpenBookingRequest();
    }
  }

  void _checkNoDriversFound() {
    if (availableDrivers.isEmpty) {
      // Debounce snackbar showing to avoid spam
      // Only show if not shown recently? For now, we rely on user patience.
    }
  }

  void _processDriverMatch(String driverId, Map<String, dynamic> driverData) {
    // 2. Filter by Destination Matching
    if (!availableDrivers.contains(driverId)) {
      if (driverData.containsKey("destination")) {
        // Enhanced Matching: Route Proximity
        bool isMatch = false;

        if (driverData.containsKey("route") &&
            (driverData["route"] as String).isNotEmpty) {
          // 1. Decode Driver's Route
          List<PointLatLng> routePoints =
              PolylinePoints().decodePolyline(driverData["route"]);

          // 2. Check Pickup Proximity & Index
          int pickupIndex = -1;
          var userPickup = pLineCoOrdinatesList.first;
          for (int i = 0; i < routePoints.length; i++) {
            var point = routePoints[i];
            if (Geolocator.distanceBetween(point.latitude, point.longitude,
                    userPickup.latitude, userPickup.longitude) <
                1000) {
              // Increased tolerance for Scheduled
              pickupIndex = i;
              break;
            }
          }

          // 3. Check Dropoff Proximity & Index
          int dropoffIndex = -1;
          var userDropOff = pLineCoOrdinatesList.last;
          for (int i = 0; i < routePoints.length; i++) {
            var point = routePoints[i];
            if (Geolocator.distanceBetween(point.latitude, point.longitude,
                    userDropOff.latitude, userDropOff.longitude) <
                1000) {
              dropoffIndex = i;
              break;
            }
          }

          // 4. Directionality Match
          if (pickupIndex != -1 &&
              dropoffIndex != -1 &&
              pickupIndex < dropoffIndex) {
            isMatch = true;

            // --- LIVE NOTIFICATION (Shadow Booking) ---
            if (!availableDrivers.contains(driverId)) {
              FirebaseFirestore.instance.collection("bookings").add({
                "scheduledTripId": "live_request_shadow",
                "driverId": driverId, // Notify THIS driver
                "riderId": FirebaseAuth.instance.currentUser!.uid,
                "riderName": userName,
                "riderPhone": userPhone,
                "riderCollege": userCollege,
                "pickup": {
                  "address": pickUpTextEditingController.text,
                  "lat": pLineCoOrdinatesList.first.latitude,
                  "lng": pLineCoOrdinatesList.first.longitude
                },
                "destination": {
                  "address": dropOffAddress,
                  "lat": pLineCoOrdinatesList.last.latitude,
                  "lng": pLineCoOrdinatesList.last.longitude
                },
                "tripDate": DateTime.now().millisecondsSinceEpoch,
                "status": "searching", // Triggers "New Request" Notification
                "created_at": FieldValue.serverTimestamp(),
                "is_live_shadow": true,
              });
            }
            // ------------------------------------------
          }
        }

        if (isMatch) {
          setState(() {
            availableDrivers.add(driverId);
          });

          if (scheduledTripDate != null) {
            // --- SCHEDULED ---
            // Add to list for selection
            driverData["id"] = driverId; // ensure ID is attached
            scheduledDriversList.add(driverData);
          } else {
            // --- LIVE ---
            // Broadcast Notify
            notifyDriver(driverId, currentRideRequestId);
          }
        }
      }
    }
  }

  void notifyDriver(String driverId, String rideRequestId) {
    // Update online_drivers/uid/newRideStatus to the rideRequestId
    FirebaseFirestore.instance
        .collection("online_drivers")
        .doc(driverId)
        .update({"newRideStatus": rideRequestId});
  }

  void showScheduledDriversDialog() {
    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return AlertDialog(
            backgroundColor: _cardColor,
            title: Text("Select a Driver",
                style: GoogleFonts.poppins(color: _textColor)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: scheduledDriversList.length,
                itemBuilder: (context, index) {
                  var d = scheduledDriversList[index];
                  int? td = d["tripDate"];
                  String time = td != null
                      ? DateFormat('hh:mm a')
                          .format(DateTime.fromMillisecondsSinceEpoch(td))
                      : "";

                  return ListTile(
                    leading: const CircleAvatar(
                        backgroundColor: Colors.grey,
                        child: Icon(Icons.person, color: Colors.white)),
                    title: Text(d["driverName"] ?? "Driver",
                        style: GoogleFonts.poppins(color: _textColor)),
                    subtitle: Text("Leaving: $time",
                        style: GoogleFonts.poppins(color: Colors.white54)),
                    trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor),
                        onPressed: () {
                          createBookingRequest(d);
                        },
                        child: const Text("Book")),
                  );
                },
              ),
            ),
          );
        });
  }

  void createBookingRequest(Map<String, dynamic> driverData) {
    Navigator.pop(context); // Close List

    FirebaseFirestore.instance.collection("bookings").add({
      "scheduledTripId": "ref_later",
      "driverId": driverData["id"],
      "driverName": driverData["driverName"] ?? "Driver",
      "driverPhone": driverData["driverPhone"] ?? "",
      "riderId": FirebaseAuth.instance.currentUser!.uid,
      "riderName": userName,
      "riderPhone": userPhone,
      "riderCollege": userCollege,
      "pickup": {
        "address": pickUpTextEditingController.text,
        "lat": pLineCoOrdinatesList.first.latitude,
        "lng": pLineCoOrdinatesList.first.longitude
      },
      "destination": {
        "address": dropOffAddress,
        "lat": pLineCoOrdinatesList.last.latitude,
        "lng": pLineCoOrdinatesList.last.longitude
      },
      "tripDate": driverData["tripDate"],
      "status": "pending",
      "createdAt": FieldValue.serverTimestamp(),
    });

    cMethods.displaySnackBar("Booking Sent! Check Activities Page.", context);

    // Reset UI to clear "Ride Requested" state
    setState(() {
      polylineSet.clear();
      markersSet.clear();
      circlesSet.clear();
      pLineCoOrdinatesList.clear();
      tripDetailsContainerHeight = 0;
      searchContainerHeight = 280; // Restore Search Container
      bottomMapPadding = 280;
      drawerOpen = true;
      scheduledTripDate = null;
    });

    // Redirect
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (c) => const Dashboard(initialIndex: 1)),
        (route) => false);
  }

  void createOpenBookingRequest() async {
    if (scheduledTripDate == null) return;

    FirebaseFirestore.instance.collection("bookings").add({
      "scheduledTripId": "ref_later",
      "driverId": "waiting", // Sentinel for Open Request
      "driverName": "Waiting for Driver",
      "driverPhone": "",
      "riderId": FirebaseAuth.instance.currentUser!.uid,
      "riderName": userName,
      "riderPhone": userPhone,
      "riderCollege": userCollege,
      "pickup": {
        "address": pickUpTextEditingController.text,
        "lat": pLineCoOrdinatesList.first.latitude,
        "lng": pLineCoOrdinatesList.first.longitude
      },
      "destination": {
        "address": dropOffAddress,
        "lat": pLineCoOrdinatesList.last.latitude,
        "lng": pLineCoOrdinatesList.last.longitude
      },
      "tripDate": scheduledTripDate!.millisecondsSinceEpoch,
      "status": "pending",
      "createdAt": FieldValue.serverTimestamp(),
    });

    // --- NOTIFY MATCHING DRIVERS (Shadow Bookings) ---
    // This queries existing scheduled trips around the same time and creates
    // a "Shadow Booking" for each driver. This ensures the Backend Cloud Function
    // (listening to 'bookings' creation) sends a specific Push Notification to them.
    int reqTime = scheduledTripDate!.millisecondsSinceEpoch;
    int window = 4 * 60 * 60 * 1000; // 4 Hours window

    FirebaseFirestore.instance
        .collection("scheduled_trips")
        .where("tripDate", isGreaterThan: reqTime - window)
        .where("tripDate", isLessThan: reqTime + window)
        .get()
        .then((snapshot) {
      for (var doc in snapshot.docs) {
        // Optional: Filter by Location Distance here if needed
        // For now, notifying all drivers with similar time is effective "Broadcasting"

        Map<String, dynamic> data = doc.data();
        if (!data.containsKey("driverId")) continue;
        String tDriverId = data["driverId"];

        FirebaseFirestore.instance.collection("bookings").add({
          "scheduledTripId": "broadcast_shadow",
          "driverId": tDriverId, // TARGET SPECIFIC DRIVER for Notification
          "riderId": FirebaseAuth.instance.currentUser!.uid,
          "riderName": userName,
          "riderPhone": userPhone,
          "riderCollege": userCollege,
          "pickup": {
            "address": pickUpTextEditingController.text,
            "lat": pLineCoOrdinatesList.first.latitude,
            "lng": pLineCoOrdinatesList.first.longitude
          },
          "destination": {
            "address": dropOffAddress,
            "lat": pLineCoOrdinatesList.last.latitude,
            "lng": pLineCoOrdinatesList.last.longitude
          },
          "tripDate": reqTime,
          "status": "searching", // Triggers "New Request" Notification
          "created_at": FieldValue.serverTimestamp(),
          "is_broadcast_shadow": true,
        });
      }
    });
    // ------------------------------------------------

    // Reset UI
    setState(() {
      polylineSet.clear();
      markersSet.clear();
      circlesSet.clear();
      pLineCoOrdinatesList.clear();
      tripDetailsContainerHeight = 0;
      searchContainerHeight = 280;
      bottomMapPadding = 280;
      drawerOpen = true;
      scheduledTripDate = null;
    });

    // Redirect to Activity Tab via Dashboard
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (c) => const Dashboard(initialIndex: 1)),
        (route) => false);
  }

  getCurrentLiveLocationOfUser() async {
    Position positionOfUser = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation));
    currentPositionOfUser = positionOfUser;

    LatLng positionOfUserInLatLng = LatLng(
        currentPositionOfUser!.latitude, currentPositionOfUser!.longitude);

    CameraPosition cameraPosition =
        CameraPosition(target: positionOfUserInLatLng, zoom: 15);
    controllerGoogleMap!
        .animateCamera(CameraUpdate.newCameraPosition(cameraPosition));

    // Reverse Geocode
    String address =
        await CommonMethods.convertGeoGraphicCoOrdinatesToHumanReadableAddress(
            positionOfUserInLatLng);

    // print("DEBUG: Fetched Address: $address");

    setState(() {
      userCurrentAddress = address;
      pickUpTextEditingController.text = address;
    });

    await getUserInfoAndCheckBlockStatus();
  }

  getUserInfoAndCheckBlockStatus() async {
    DocumentSnapshot userParams = await FirebaseFirestore.instance
        .collection("users")
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();

    if (!mounted) return;

    if (userParams.exists) {
      if ((userParams.data() as Map)["blockStatus"] == "no") {
        setState(() {
          userName = (userParams.data() as Map)["name"] ?? "";
          userPhone = (userParams.data() as Map)["phone"] ?? "";
          userCollege =
              (userParams.data() as Map)["collegeName"] ?? "College Not Found";
          // Fetch Verification Data
          String vStatus =
              (userParams.data() as Map)["verificationStatus"] ?? "pending";
          bool hasRejection =
              (userParams.data() as Map)["hasPriorRejection"] ?? false;

          // Store globally or in state (assuming logic is local for now)
          // Ideally we should use a model, but simpler to use local vars if not used elsewhere
          // But 'saveRideRequestInformation' is outside build, so we need state vars.
          // Let's add them to the class state first.
          verificationStatus = vStatus;
          hasPriorRejection = hasRejection;
        });
      } else {
        FirebaseAuth.instance.signOut();

        Navigator.push(
            context, MaterialPageRoute(builder: (c) => const LoginScreen()));

        cMethods.displaySnackBar(
            "Your are Blocked. Please contact the admin.", context);
      }
    } else {
      FirebaseAuth.instance.signOut();
      Navigator.push(
          context, MaterialPageRoute(builder: (c) => const LoginScreen()));
    }
  }

  void createMarkerIcon() {
    if (carMarkerIcon == null) {
      ImageConfiguration imageConfiguration =
          createLocalImageConfiguration(context, size: const Size(2, 2));
      BitmapDescriptor.asset(imageConfiguration, "assets/images/tracking.png")
          .then((icon) {
        carMarkerIcon = icon;
      });
    }
  }

  void listenToDriverLocation(String driverId) {
    driverLocationSubscription = FirebaseFirestore.instance
        .collection("online_drivers")
        .doc(driverId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        if (!mounted) return;
        var driverPosition = snapshot.data()?["position"];
        if (driverPosition != null) {
          double driverLat = driverPosition["geopoint"].latitude;
          double driverLng = driverPosition["geopoint"].longitude;
          LatLng driverLatLng = LatLng(driverLat, driverLng);

          Marker driverMarker = Marker(
            markerId: const MarkerId("driverMarker"),
            position: driverLatLng,
            icon: carMarkerIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueViolet),
            infoWindow: const InfoWindow(title: "Your Driver"),
          );

          setState(() {
            markersSet.removeWhere(
                (marker) => marker.markerId.value == "driverMarker");
            markersSet.add(driverMarker);
          });

          // Animate camera to follow driver if needed
          controllerGoogleMap
              ?.animateCamera(CameraUpdate.newLatLng(driverLatLng));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
              padding: EdgeInsets.only(top: 26, bottom: bottomMapPadding),
              mapType: MapType.normal,
              myLocationEnabled: true,
              initialCameraPosition: googlePlexInitialPosition,
              polylines: polylineSet,
              markers: markersSet,
              circles: circlesSet,
              onMapCreated: (GoogleMapController mapController) {
                controllerGoogleMap = mapController;
                updateMapTheme(controllerGoogleMap!);
                googleMapCompleterController.complete(controllerGoogleMap);

                setState(() {
                  bottomMapPadding = 120;
                });

                getCurrentLiveLocationOfUser();
              }),

          // Trip Details Container
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: tripDetailsContainerHeight,
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 15,
                    spreadRadius: 5,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Request a Ride",
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          color: _textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Distance and Time
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tripDirectionDetails?.distanceTextString ?? "",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            tripDirectionDetails?.durationTextString ?? "",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Suggested Fare
                      Text(
                        "Suggested Fare: ₹${CommonMethods.calculateFareAmount(tripDirectionDetails ?? DirectionDetails(distanceValueDigits: 0))}",
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white54,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // User Offer Input
                      TextField(
                        controller: offerAmountTextEditingController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.poppins(
                            color: _textColor, fontSize: 18),
                        decoration: InputDecoration(
                          hintText: "Enter your offer",
                          hintStyle: GoogleFonts.poppins(color: Colors.white38),
                          prefixText: "₹ ",
                          prefixStyle: GoogleFonts.poppins(
                              color: _accentColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                          fillColor: Colors.black.withOpacity(0.3),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide:
                                BorderSide(color: _accentColor, width: 1.5),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Request Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            if (offerAmountTextEditingController.text
                                .trim()
                                .isEmpty) {
                              cMethods.displaySnackBar(
                                  "Please enter your offer.", context);
                              return;
                            }

                            // Just a visual confirmation for now
                            // cMethods.displaySnackBar("Requesting Ride... (Logic Pending)", context);

                            // Verification Block Logic
                            if (verificationStatus == "rejected") {
                              cMethods.displaySnackBar(
                                  "Your ID was rejected. Please upload a new one to request rides.",
                                  context,
                                  isError: true);
                              return;
                            }
                            if (verificationStatus == "pending" &&
                                hasPriorRejection) {
                              cMethods.displaySnackBar(
                                  "Verification Pending. You cannot request rides until your re-uploaded ID is approved.",
                                  context);
                              return;
                            }

                            saveRideRequestInformation();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 8,
                            shadowColor: _accentColor.withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            "Request Ride",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // Cancel Button
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              searchContainerHeight = 276;
                              tripDetailsContainerHeight = 0;
                              bottomMapPadding =
                                  300; // Reset padding when container closes
                              polylineSet.clear();
                              markersSet.clear();
                              circlesSet.clear();
                              pLineCoOrdinatesList.clear();
                            });
                          },
                          child: Text(
                            "Cancel",
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Driver Details & OTP Container
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: driverDetailsContainerHeight,
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 15,
                    spreadRadius: 5,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Title + OTP
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            rideStatusText,
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              color: _textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // Small OTP Badge
                          if (!isTripStarted)
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: _accentColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: _accentColor)),
                                child: Row(
                                  children: [
                                    Text("OTP: ",
                                        style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    Text(rideOtp,
                                        style: GoogleFonts.poppins(
                                            color: _textColor,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ))
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Driver Info Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            const CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.white24,
                              child: Icon(Icons.person,
                                  size: 30, color: Colors.white),
                            ),
                            const SizedBox(width: 16),

                            // Text Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      driverName == "Rider"
                                          ? "Driver"
                                          : driverName,
                                      style: GoogleFonts.poppins(
                                          color: _textColor,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                  Text(driverCollege,
                                      style: GoogleFonts.poppins(
                                          color: Colors.white54, fontSize: 14)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Chat & Call Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Chat Button
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (c) => ChatScreen(
                                          rideRequestId: currentRideRequestId,
                                          otherUserName: driverName)));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2196F3),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.blue.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.chat_bubble,
                                      color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text("Chat",
                                      style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),

                          GestureDetector(
                            onTap: () async {
                              if (driverPhone.isNotEmpty) {
                                final Uri launchUri = Uri(
                                  scheme: 'tel',
                                  path: driverPhone,
                                );
                                try {
                                  if (await canLaunchUrl(launchUri)) {
                                    await launchUrl(launchUri);
                                  } else {
                                    // Fallback for some devices
                                    await launchUrl(launchUri);
                                  }
                                } catch (e) {
                                  cMethods.displaySnackBar(
                                      "Could not launch dialer: $e", context);
                                }
                              } else {
                                cMethods.displaySnackBar(
                                    "Phone number not available", context);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.green.withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.phone,
                                      color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text("Call",
                                      style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // SOS / Share Ride Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (currentRideRequestId.isEmpty) return;

                            String shareText = "🚨 SOS / Ride Details 🚨\n\n"
                                "I am on a ride with Jinete.\n"
                                "Driver: $driverName\n"
                                "Phone: $driverPhone\n"
                                "College: $driverCollege\n"
                                "Car Status: On Trip\n\n"
                                "Track me: (App Link)";

                            Share.share(shareText);
                          },
                          icon: const Icon(Icons.share_location,
                              color: Colors.white),
                          label: Text(
                            "Share Ride Details (SOS)",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent.shade700,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Cancel Trip Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            // Show Confirmation Dialog
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text("Cancel Trip"),
                                content: const Text(
                                    "Are you sure you want to cancel this trip?"),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("No"),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);

                                      // 1. Update Firestore
                                      FirebaseFirestore.instance
                                          .collection("rideRequests")
                                          .doc(currentRideRequestId)
                                          .update({
                                        "status": "cancelled",
                                        "cancelled_by": "rider",
                                      });

                                      // 2. Reset UI
                                      setState(() {
                                        driverDetailsContainerHeight = 0;
                                        searchContainerHeight = 276;
                                        bottomMapPadding = 300;
                                        polylineSet.clear();
                                        markersSet.clear();
                                        circlesSet.clear();
                                        pLineCoOrdinatesList.clear();
                                        tripDirectionDetails =
                                            null; // Clear details
                                        isTripStarted = false;
                                      });

                                      cMethods.displaySnackBar(
                                          "Trip Cancelled Successfully",
                                          context);
                                    },
                                    child: const Text("Yes, Cancel",
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent.withOpacity(0.1),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Colors.redAccent),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                            "Cancel Trip",
                            style: GoogleFonts.poppins(
                              color: Colors.redAccent,
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
            ),
          ),

          // SEARCH LOCATION CONTAINER - RESTORED & MOVED TO END
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: searchContainerHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF181820),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, -5),
                  ),
                ],
                border: Border.all(
                  color: Colors.white24, // Subtle but visible border
                  width: 1.0,
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Where to?",
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () async {
                        var responseFromSearchScreen = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (c) => SearchDestinationPage()));

                        if (responseFromSearchScreen != null) {
                          // Parse response Map
                          Map<String, dynamic> responseMap =
                              responseFromSearchScreen as Map<String, dynamic>;

                          // 1. Determine Start Point (Pickup)
                          LatLng startLatLng;
                          if (responseMap.containsKey("pickup")) {
                            startLatLng = LatLng(
                              responseMap["pickup"]["lat"],
                              responseMap["pickup"]["lng"],
                            );
                            setState(() {
                              userCurrentAddress =
                                  responseMap["pickup"]["address"];
                            });
                          } else {
                            startLatLng = LatLng(
                              currentPositionOfUser!.latitude,
                              currentPositionOfUser!.longitude,
                            );
                          }

                          // 2. Determine End Point (Dropoff)
                          if (responseMap.containsKey("dropoff")) {
                            LatLng endLatLng = LatLng(
                              responseMap["dropoff"]["lat"],
                              responseMap["dropoff"]["lng"],
                            );

                            dropOffAddress = responseMap["dropoff"]["address"];

                            // 3. Get Directions
                            var details =
                                await CommonMethods.getDirectionDetails(
                                    startLatLng, endLatLng);
                            if (details != null) {
                              // Capture Trip Date
                              if (responseMap.containsKey("tripDate")) {
                                setState(() {
                                  scheduledTripDate =
                                      DateTime.fromMillisecondsSinceEpoch(
                                          responseMap["tripDate"]);
                                });
                              } else {
                                setState(() {
                                  scheduledTripDate = null;
                                });
                              }

                              await retrieveDirectionDetails(details);
                            }
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(50),
                          border: Border.all(color: Colors.white12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "Search Destination",
                              style: GoogleFonts.poppins(
                                color: Colors.white54,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Accepted Ride Banner - Removed to use unified Driver Details Container
          // _buildAcceptedRideBanner(),
        ],
      ),
    );
  }

  // Method _buildAcceptedRideBanner removed as it is superseded by main driver details container.

  void resetApp() {
    setState(() {
      searchContainerHeight = 276;
      tripDetailsContainerHeight = 0;
      driverDetailsContainerHeight = 0;
      bottomMapPadding = 300;
      polylineSet.clear();
      markersSet.clear();
      circlesSet.clear();
      pLineCoOrdinatesList.clear();
      tripDirectionDetails = null;
      currentRideRequestId = "";
      isTripStarted = false;
      driverLocationSubscription?.cancel();
      driverLocationSubscription = null;
      rideStreamSubscription?.cancel();
      rideStreamSubscription = null;
      carMarkerIcon = null;
    });
  }
}
