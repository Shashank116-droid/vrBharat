import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:jinete/global/global_var.dart';
import 'package:jinete/models/direction_details.dart';
import 'package:geocoding/geocoding.dart';
import 'package:jinete/models/place_prediction.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CommonMethods {
  Future<void> checkConnectivity(BuildContext context) async {
    var connectionResult = await Connectivity().checkConnectivity();

    if (connectionResult != ConnectivityResult.mobile &&
        connectionResult != ConnectivityResult.wifi) {
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
    String autoCompleteUrl =
        "https://places.googleapis.com/v1/places:autocomplete";

    var response = await http.post(
      Uri.parse(autoCompleteUrl),
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": googleMapKey,
      },
      body: jsonEncode({
        "input": placeName,
        "includedRegionCodes": ["in"], // Limit to India
      }),
    );

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      if (data["suggestions"] != null) {
        var predictionArgs = data["suggestions"];
        return (predictionArgs as List)
            .map((e) => PlacePrediction.fromJson(e))
            .toList();
      }
    } else {
      // Log error if any
      var data = jsonDecode(response.body);
    }
    return [];
  }

  static Future<DirectionDetails?> getDirectionDetails(
      LatLng startPosition, LatLng endPosition) async {
    String urlDirectionAPI =
        "https://maps.googleapis.com/maps/api/directions/json?origin=${startPosition.latitude},${startPosition.longitude}&destination=${endPosition.latitude},${endPosition.longitude}&alternatives=true&key=$googleMapKey";

    var response = await http.get(Uri.parse(urlDirectionAPI));

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);

      if (data["status"] == "OK") {
        DirectionDetails directionDetails = DirectionDetails();

        // Find shortest route (min distance)
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
    return null;
  }

  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    String placeDetailsUrl =
        "https://places.googleapis.com/v1/places/$placeId?fields=location&key=$googleMapKey";

    var response = await http.get(Uri.parse(placeDetailsUrl));

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return data;
    }
    return null;
  }

  static double calculateFareAmount(DirectionDetails directionDetails) {
    double distancePerKmAmount = 5;
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
    if (humanReadableAddress.isEmpty || humanReadableAddress.length < 5 || humanReadableAddress.contains(RegExp(r'[0-9]+.[0-9]+, [0-9]+.[0-9]+'))) {
        String osmUrl = 
          "https://nominatim.openstreetmap.org/reverse?format=json&lat=${latLng.latitude}&lon=${latLng.longitude}&zoom=18&addressdetails=1";
        
        try {
          var response = await http.get(Uri.parse(osmUrl), headers: {
            "User-Agent": "JineteCarpoolApp/1.0 (flutter_app)" // Required by Nominatim
          });
          
          if (response.statusCode == 200) {
             var data = jsonDecode(response.body);
             if (data["display_name"] != null) {
               humanReadableAddress = data["display_name"];
             }
          }
        } catch(e) {
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
