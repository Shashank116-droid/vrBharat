import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:jinete_driver_app/global/global_var.dart';
import 'package:geocoding/geocoding.dart';

class CommonMethods {
  Future<void> checkConnectivity(BuildContext context) async {
    var connectionResult = await Connectivity().checkConnectivity();

    if (connectionResult != ConnectivityResult.mobile &&
        connectionResult != ConnectivityResult.wifi) {
      if (!context.mounted) return;
      displaySnackBar(
        "Internet is not Available. Please check your connection and Try Again",
        context,
      );
    }
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

    var response = await http.get(Uri.parse(urlDirectionAPI));

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
      }
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
