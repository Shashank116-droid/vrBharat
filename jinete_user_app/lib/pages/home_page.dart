import "dart:math";

import 'package:cloud_firestore/cloud_firestore.dart';
import "dart:async";
import "dart:convert";
import "dart:typed_data";
import 'package:geoflutterfire2/geoflutterfire2.dart';
import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:google_fonts/google_fonts.dart";
import "package:geolocator/geolocator.dart";
import "package:google_maps_flutter/google_maps_flutter.dart";
import "package:jinete/authentication/login_screen.dart";
import 'package:jinete/pages/chat_screen.dart'; // Added
import "package:jinete/global/global_var.dart";
import "package:jinete/methods/common_methods.dart";
import "package:jinete/pages/search_destination_page.dart";
import "package:flutter_polyline_points/flutter_polyline_points.dart";
import "package:jinete/models/direction_details.dart";
import "package:url_launcher/url_launcher.dart";
import "package:jinete/push_notification/push_notification_service.dart";

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
  GlobalKey<ScaffoldState> sKey = GlobalKey<ScaffoldState>();
  CommonMethods cMethods = CommonMethods();
  double searchContainerHeight = 276;
  double tripDetailsContainerHeight = 0; // Starts hidden
  double driverDetailsContainerHeight = 0; // Starts hidden
  double bottomMapPadding = 0;

  String rideOtp = "";
  bool isTripStarted = false;
  String driverName = "Driver";
  String driverPhone = "";
  String driverCollege = "";
  String rideStatusText = "Driver Arriving";

  String userCollege = ""; // For sending to driver
  StreamSubscription<DocumentSnapshot>? driverLocationSubscription;
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

  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;

  @override
  void initState() {
    super.initState();
    PushNotificationService.initializeNotification();
    getUserInfo();
    getUserInfo();
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
          userName = snap.data()?["name"] ?? "";
          userPhone = snap.data()?["phone"] ?? "";
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
    print(
        "DEBUG: retrieveDirectionDetails called. Points: ${directionDetails.encodedPoints?.length}");

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
      print(
          "DEBUG: Updating UI with polyline. Coordinates: ${pLineCoOrdinatesList.length}");
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
      "rider_name": userName,
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

    FirebaseFirestore.instance
        .collection("rideRequests")
        .doc(currentRideRequestId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        if (!mounted) return;

        String status = snapshot.data()?["status"] ?? "";
        String counterOffer = snapshot.data()?["counter_offer"] ?? "0";
        String otp = snapshot.data()?["otp"] ?? "";

        // 1. Check for Acceptance
        if (status == "accepted") {
          print("DEBUG: Snapshot Data: ${snapshot.data()}"); // Dump all data
          // Fetch driver details if needed
          driverName = snapshot.data()?["driver_name"] ?? "Driver";
          driverPhone = snapshot.data()?["driver_phone"] ?? "";
          driverCollege =
              snapshot.data()?["driver_college"] ?? "College Info Unavailable";

          // DEBUG: Print received data
          print(
              "DEBUG: Driver Info - name: $driverName, phone: $driverPhone, college: $driverCollege, OTP: $otp");

          rideOtp = otp;

          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close "Searching..." Dialog
          }

          // Start Listening to Driver Location
          listenToDriverLocation(snapshot.data()?["driver_id"] ?? "");

          setState(() {
            searchContainerHeight = 0;
            tripDetailsContainerHeight = 0;
            driverDetailsContainerHeight = 300;
            bottomMapPadding = 320;
            rideStatusText = "Driver Arriving";
          });
        }
        // 2. Check for Driver Arrival
        else if (status == "arrived") {
          setState(() {
            rideStatusText = "Driver Arrived";
          });
          // Show a local notification and snackbar
          PushNotificationService.showNotification("Driver Arrived",
              "Your ride has arrived, please share the OTP with your driver.");
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
        // 2. Check for Counter Offer
        else if (counterOffer != "0" &&
            counterOffer != offerAmountTextEditingController.text) {
          showCounterOfferDialog(counterOffer);
        }
        // 4. Check for Trip End
        else if (status == "completed") {
          // 1. Stop Tracking
          resetApp();

          // 2. Show Dialog
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
                            },
                            child: const Text("Pay & Rate"))
                      ]));
        }
        // 5. Check for Cancellation
        else if (status == "cancelled") {
          // Only show alert if cancelled by DRIVER
          String cancelledBy = snapshot.data()?["cancelled_by"] ?? "";
          if (cancelledBy == "driver") {
            PushNotificationService.showNotification("Ride Cancelled",
                "The Driver has cancelled the Ride. Please request another Ride.");

            resetApp();

            // Close any open dialogs
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }

            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext c) => AlertDialog(
                backgroundColor: const Color(0xFF181820),
                title: const Text(
                  "Ride Cancelled",
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  "The Driver has cancelled the Ride. Please request another Ride.",
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(c);
                    },
                    child: const Text(
                      "OK",
                      style: TextStyle(color: Colors.white),
                    ),
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

    final geo = GeoFlutterFire();
    GeoFirePoint center = geo.point(
        latitude: pLineCoOrdinatesList[0].latitude,
        longitude: pLineCoOrdinatesList[0].longitude);

    print(
        "DEBUG: User Searching at ${center.latitude}, ${center.longitude} with Radius 20km");

    var collectionReference =
        FirebaseFirestore.instance.collection('online_drivers');

    Stream<List<DocumentSnapshot>> stream = geo
        .collection(collectionRef: collectionReference)
        .within(center: center, radius: 20, field: 'position');

    stream.listen((List<DocumentSnapshot> documentList) {
      print("DEBUG: Geoflutterfire found ${documentList.length} drivers");

      for (DocumentSnapshot doc in documentList) {
        if (!availableDrivers.contains(doc.id)) {
          availableDrivers.add(doc.id);
          print("DEBUG: Driver Found! ID: ${doc.id}");
          notifyDriver(doc.id, rideRequestId);
        }
      }

      if (availableDrivers.isEmpty) {
        if (!mounted) return;
        cMethods.displaySnackBar("No online drivers found nearby.", context);
      }
    });
  }

  void notifyDriver(String driverId, String rideRequestId) {
    // Update online_drivers/uid/newRideStatus to the rideRequestId
    FirebaseFirestore.instance
        .collection("online_drivers")
        .doc(driverId)
        .update({"newRideStatus": rideRequestId});
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

    print("DEBUG: Fetched Address: $address"); // Debug log

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
          userName = (userParams.data() as Map)["name"];
          userPhone = (userParams.data() as Map)["phone"];
          userCollege =
              (userParams.data() as Map)["collegeName"] ?? "College Not Found";
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

          /// search location iconButton
          // Search Container
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: searchContainerHeight,
              decoration: BoxDecoration(
                color: _backgroundColor,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Where to?",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        color: _textColor,
                        fontWeight: FontWeight.w600,
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
                            // Manual Pickup Selected
                            startLatLng = LatLng(
                              responseMap["pickup"]["lat"],
                              responseMap["pickup"]["lng"],
                            );
                            // Update Pickup Address
                            setState(() {
                              userCurrentAddress =
                                  responseMap["pickup"]["address"];
                            });
                          } else {
                            // Default to Current Location
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

                            // Update Dropoff Name for UI
                            dropOffAddress = responseMap["dropoff"]["address"];

                            // 3. Get Directions
                            var details =
                                await CommonMethods.getDirectionDetails(
                                    startLatLng, endLatLng);
                            if (details != null) {
                              await retrieveDirectionDetails(details);
                            }
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
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
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

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
                      style:
                          GoogleFonts.poppins(color: _textColor, fontSize: 18),
                      decoration: InputDecoration(
                        hintText: "Enter your offer",
                        hintStyle: GoogleFonts.poppins(color: Colors.white24),
                        prefixText: "₹ ",
                        prefixStyle: GoogleFonts.poppins(
                            color: _accentColor, fontSize: 18),
                        fillColor: Colors.white10,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
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

                          saveRideRequestInformation();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
                        // Small OTP Badge - Only show if trip hasn't started
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
                                          color: Colors.white70, fontSize: 12)),
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
                        color: _cardColor, // Or slightly lighter?
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
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
                                Text(driverName,
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
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(50)),
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

                        // Call Button
                        GestureDetector(
                          onTap: () {
                            if (driverPhone.isNotEmpty) {
                              launchUrl(Uri.parse("tel://$driverPhone"));
                            } else {
                              cMethods.displaySnackBar(
                                  "Phone number not available", context);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(50)),
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
                                        "Trip Cancelled Successfully", context);
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
        ],
      ),
    );
  }

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
      carMarkerIcon = null;
    });
  }
}
