import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:jinete_driver_app/global/global_var.dart';
import 'package:geocoding/geocoding.dart';

class CommonMethods {
  Future<bool> checkConnectivity(BuildContext context) async {
    var connectionResult = await Connectivity().checkConnectivity();

    if (connectionResult == ConnectivityResult.none) {
      if (!context.mounted) return false;
      displaySnackBar(
        "Internet is not Available. Please check your connection and Try Again",
        context,
      );
      return false;
    }
    return true;
  }

  void displaySnackBar(String messageText, BuildContext context) {
    var snackBar = SnackBar(content: Text(messageText));
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  static Future<DirectionDetails?> getDirectionDetails(
    LatLng origin,
    LatLng destination,
  ) async {
    String urlDirectionAPI =
        "https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&key=$googleMapKey";

    var headers = {
      "X-Android-Package": "com.vrbharat.jinete_driver_app",
      "X-Android-Cert": kDebugMode
          ? "B6:08:45:A6:53:6E:88:C2:63:2A:0F:60:C9:8A:69:C9:70:27:AA:CF" // Debug SHA-1
          : "BC:5D:6F:7F:3B:90:3B:75:BD:E4:99:35:24:19:36:65:2A:57:C6:A0", // Release SHA-1
    };

    print("DEBUG: API Key Headers: $headers");

    try {
      var response = await http.get(
        Uri.parse(urlDirectionAPI),
        headers: headers,
      );

      print("Directions API Status Code: ${response.statusCode}");
      print("Directions API Body: ${response.body}");

      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(response.body);

        if (jsonResponse["status"] == "OK") {
          DirectionDetails directionDetails = DirectionDetails();
          directionDetails.distanceText =
              jsonResponse["routes"][0]["legs"][0]["distance"]["text"];
          directionDetails.distanceValue =
              jsonResponse["routes"][0]["legs"][0]["distance"]["value"];
          directionDetails.durationText =
              jsonResponse["routes"][0]["legs"][0]["duration"]["text"];
          directionDetails.durationValue =
              jsonResponse["routes"][0]["legs"][0]["duration"]["value"];
          directionDetails.encodedPoints =
              jsonResponse["routes"][0]["overview_polyline"]["points"];

          return directionDetails;
        } else {
          print("Directions API Error Status: ${jsonResponse["status"]}");
          print("Error Message: ${jsonResponse["error_message"]}");
        }
      } else {
        print("Directions API HTTP Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Error in Google Directions API: $e");
    }
    return null;
  }

  static Future<String> convertGeoGraphicCoOrdinatesToHumanReadableAddress(
    LatLng latLng,
  ) async {
    String humanReadableAddress = "";

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        humanReadableAddress =
            "${place.name ?? ''} ${place.thoroughfare ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''} ${place.postalCode ?? ''}";
        humanReadableAddress = humanReadableAddress
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (humanReadableAddress.startsWith(","))
          humanReadableAddress = humanReadableAddress.substring(1).trim();
      }
    } catch (e) {
      print("DEBUG: Native Geocoding Error: $e");
    }

    if (humanReadableAddress.isEmpty || humanReadableAddress.length < 5) {
      String apiUrl =
          "https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}&key=$googleMapKey";

      try {
        var response = await http.get(
          Uri.parse(apiUrl),
          headers: {
            "X-Android-Package": "com.vrbharat.jinete_driver_app",
            "X-Android-Cert": kDebugMode
                ? "B6:08:45:A6:53:6E:88:C2:63:2A:0F:60:C9:8A:69:C9:70:27:AA:CF" // Debug SHA-1
                : "BC:5D:6F:7F:3B:90:3B:75:BD:E4:99:35:24:19:36:65:2A:57:C6:A0", // Release SHA-1
          },
        );
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

    // 3. Fallback to OpenStreetMap (Nominatim)
    if (humanReadableAddress.isEmpty ||
        humanReadableAddress.length < 5 ||
        humanReadableAddress.contains(
          RegExp(r'[0-9]+.[0-9]+, [0-9]+.[0-9]+'),
        )) {
      String osmUrl =
          "https://nominatim.openstreetmap.org/reverse?format=json&lat=${latLng.latitude}&lon=${latLng.longitude}&zoom=18&addressdetails=1";

      try {
        var response = await http.get(
          Uri.parse(osmUrl),
          headers: {"User-Agent": "JineteDriverApp/1.0 (flutter_app)"},
        );

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
}

class DirectionDetails {
  String? distanceText;
  String? durationText;
  int? distanceValue;
  int? durationValue;
  String? encodedPoints;

  DirectionDetails({
    this.distanceText,
    this.durationText,
    this.distanceValue,
    this.durationValue,
    this.encodedPoints,
  });
}
