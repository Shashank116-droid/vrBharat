import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:jinete/global/global_var.dart';
import 'package:jinete/models/direction_details.dart';
import 'package:geocoding/geocoding.dart';
import 'package:jinete/models/place_prediction.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flutter_google_places_sdk/flutter_google_places_sdk.dart'
    as places_sdk;

// ... (keep imports)

class CommonMethods {
  // Initialize SDK
  static final places_sdk.FlutterGooglePlacesSdk _placesSdk =
      places_sdk.FlutterGooglePlacesSdk(googleMapKey);

  Future<void> checkConnectivity(BuildContext context) async {
    var connectionResult = await Connectivity().checkConnectivity();

    if (!connectionResult.contains(ConnectivityResult.mobile) &&
        !connectionResult.contains(ConnectivityResult.wifi)) {
      if (!context.mounted) return;
      displaySnackBar(
          "Internet is not Available. Please check your connection and Try Again",
          context);
    }
  }

  void displaySnackBar(String messageText, BuildContext context,
      {bool isError = false}) {
    var snackBar = SnackBar(
      content: Text(
        messageText,
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      duration: const Duration(seconds: 4),
    );
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  static Future<List<PlacePrediction>> searchPlace(String placeName) async {
    if (placeName.length < 2) return [];

    try {
      final response = await _placesSdk.findAutocompletePredictions(
        placeName,
        countries: ['in'], // Limit to India
      );

      if (response.predictions.isNotEmpty) {
        return response.predictions.map((p) {
          return PlacePrediction(
            placeId: p.placeId,
            mainText: p.primaryText,
            secondaryText: p.secondaryText,
          );
        }).toList();
      }
    } catch (e) {
      print("Error Occurred during prediction: $e");
    }
    return [];
  }

  static Future<DirectionDetails?> getDirectionDetails(
      LatLng startPosition, LatLng endPosition) async {
    String urlDirectionAPI =
        "https://maps.googleapis.com/maps/api/directions/json?origin=${startPosition.latitude},${startPosition.longitude}&destination=${endPosition.latitude},${endPosition.longitude}&alternatives=true&key=$googleMapKey";

    try {
      print("DEBUG: Fetching directions from $startPosition to $endPosition");
      var response = await http.get(
        Uri.parse(urlDirectionAPI),
        headers: {
          "X-Android-Package": "com.vrbharat.jinete_user_app",
          "X-Android-Cert": kDebugMode
              ? "B6:08:45:A6:53:6E:88:C2:63:2A:0F:60:C9:8A:69:C9:70:27:AA:CF" // Debug SHA-1
              : "6C:BC:0E:56:58:6F:F3:A8:71:37:39:2C:4A:98:23:5E:57:D9:C3:CB", // Release SHA-1
        },
      );
      print("DEBUG: Directions API Response Code: ${response.statusCode}");
      print("DEBUG: Directions API Response Body: ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        if (data["status"] == "OK") {
          DirectionDetails directionDetails = DirectionDetails();
          var routes = data["routes"] as List;
          var shortestRoute = routes[0];
          int minDistance = shortestRoute["legs"][0]["distance"]["value"];

          for (var route in routes) {
            int distance = route["legs"][0]["distance"]["value"];
            if (distance < minDistance) {
              minDistance = distance;
              shortestRoute = route;
            }
          }

          directionDetails.distanceTextString =
              shortestRoute["legs"][0]["distance"]["text"];
          directionDetails.distanceValueDigits =
              shortestRoute["legs"][0]["distance"]["value"];
          directionDetails.durationTextString =
              shortestRoute["legs"][0]["duration"]["text"];
          directionDetails.durationValueDigits =
              shortestRoute["legs"][0]["duration"]["value"];
          directionDetails.encodedPoints =
              shortestRoute["overview_polyline"]["points"];

          return directionDetails;
        }
      }
    } catch (e) {
      print("Error in Google Directions API: $e");
    }

    // FALLBACK: OSRM (Open Source Routing Machine)
    print("DEBUG: Switching to OSRM Fallback for Directions...");
    String osrmUrl =
        "https://router.project-osrm.org/route/v1/driving/${startPosition.longitude},${startPosition.latitude};${endPosition.longitude},${endPosition.latitude}?overview=full&geometries=polyline";

    try {
      var response = await http.get(Uri.parse(osrmUrl));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data["code"] == "Ok") {
          DirectionDetails directionDetails = DirectionDetails();
          var route = data["routes"][0];

          // OSRM returns distance in meters, duration in seconds
          int distanceVal = (route["distance"] as num).toInt();
          int durationVal = (route["duration"] as num).toInt();

          directionDetails.distanceValueDigits = distanceVal;
          directionDetails.durationValueDigits = durationVal;

          // Format Text (Simple)
          directionDetails.distanceTextString =
              "${(distanceVal / 1000).toStringAsFixed(1)} km";
          directionDetails.durationTextString =
              "${(durationVal / 60).ceil()} min";

          directionDetails.encodedPoints = route["geometry"];

          return directionDetails;
        }
      }
    } catch (e) {
      print("Error in OSRM API: $e");
    }

    return null;
  }

  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    try {
      print("DEBUG: Fetching details via Native SDK for Place ID: $placeId");

      // Fetch ONLY Location to minimize crash risk
      final response = await _placesSdk.fetchPlace(
        placeId,
        fields: [places_sdk.PlaceField.Location],
      );

      print("DEBUG: Native SDK Response: ${response.place}");

      if (response.place != null) {
        print("DEBUG: Place Object: ${response.place}");
        if (response.place!.latLng != null) {
          print("DEBUG: LatLng Found: ${response.place!.latLng}");
          return {
            "location": {
              "latitude": response.place!.latLng!.lat,
              "longitude": response.place!.latLng!.lng,
            }
          };
        } else {
          print("DEBUG: LatLng is NULL in response");
        }
      } else {
        print("DEBUG: Place Object is NULL");
      }
    } catch (e) {
      print("DEBUG: Native SDK Error: $e");
    }
    return null;
  }

  static double calculateFareAmount(DirectionDetails directionDetails) {
    double distancePerKmAmount = 1.9;
    double baseFareAmount = 20;

    double totalDistance = directionDetails.distanceValueDigits! / 1000;

    double totalFareAmount =
        baseFareAmount + (totalDistance * distancePerKmAmount);

    return double.parse(totalFareAmount.toStringAsFixed(1));
  }

  static Future<String> convertGeoGraphicCoOrdinatesToHumanReadableAddress(
      LatLng latLng) async {
    String humanReadableAddress = "";

    // 1. Try Native Geocoding
    try {
      List<Placemark> placemarks =
          await placemarkFromCoordinates(latLng.latitude, latLng.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        humanReadableAddress =
            "${place.name ?? ''} ${place.thoroughfare ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''} ${place.postalCode ?? ''}";
        humanReadableAddress =
            humanReadableAddress.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (humanReadableAddress.startsWith(","))
          humanReadableAddress = humanReadableAddress.substring(1).trim();
      }
    } catch (e) {
      print("DEBUG: Native Geocoding Error: $e");
    }

    // 2. Fallback to HTTP
    if (humanReadableAddress.isEmpty || humanReadableAddress.length < 5) {
      String apiUrl =
          "https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}&key=$googleMapKey";
      try {
        var response = await http.get(Uri.parse(apiUrl));
        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          if (data["status"] == "OK" && data["results"].isNotEmpty) {
            humanReadableAddress = data["results"][0]["formatted_address"];
          }
        }
      } catch (e) {
        print("DEBUG: API Geocoding Error: $e");
      }
    }

    // 3. Fallback to OpenStreetMap (Nominatim) - Free, No Key
    if (humanReadableAddress.isEmpty ||
        humanReadableAddress.length < 5 ||
        humanReadableAddress
            .contains(RegExp(r'[0-9]+.[0-9]+, [0-9]+.[0-9]+'))) {
      String osmUrl =
          "https://nominatim.openstreetmap.org/reverse?format=json&lat=${latLng.latitude}&lon=${latLng.longitude}&zoom=18&addressdetails=1";

      try {
        var response = await http.get(Uri.parse(osmUrl), headers: {
          "User-Agent":
              "JineteCarpoolApp/1.0 (flutter_app)" // Required by Nominatim
        });

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          if (data["display_name"] != null) {
            humanReadableAddress = data["display_name"];
          }
        }
      } catch (e) {
        print("DEBUG: OSM Geocoding Error: $e");
      }
    }

    if (humanReadableAddress.isEmpty) {
      return "${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}";
    }

    return humanReadableAddress;
  }

  Route createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }
}
