import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete/methods/common_methods.dart';
import 'package:jinete/models/place_prediction.dart';
import 'dart:async';

class SearchDestinationPage extends StatefulWidget {
  const SearchDestinationPage({super.key});

  @override
  State<SearchDestinationPage> createState() => _SearchDestinationPageState();
}

class _SearchDestinationPageState extends State<SearchDestinationPage> {
  TextEditingController pickUpTextEditingController = TextEditingController();
  TextEditingController dropOffTextEditingController = TextEditingController();
  List<PlacePrediction> placePredictionList = [];
  Timer? _debounce;

  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _inputColor = const Color(0xFF252530);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;
  final Color _hintColor = Colors.white54;

  FocusNode pickUpFocusNode = FocusNode();
  FocusNode dropOffFocusNode = FocusNode();
  bool isPickupFocused = false;

  // Store coordinates
  double? pickupLat;
  double? pickupLng;
  double? dropoffLat;
  double? dropoffLng;

  @override
  void initState() {
    super.initState();
    pickUpTextEditingController.text = "My Current Location";

    pickUpFocusNode.addListener(() {
      if (pickUpFocusNode.hasFocus) {
        setState(() {
          isPickupFocused = true;
        });
      }
    });

    dropOffFocusNode.addListener(() {
      if (dropOffFocusNode.hasFocus) {
        setState(() {
          isPickupFocused = false;
        });
      }
    });
  }

  @override
  void dispose() {
    pickUpFocusNode.dispose();
    dropOffFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Back Button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        color: _textColor,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    "Set Drop-off",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Search Inputs Container
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Pick Up Row
                  Row(
                    children: [
                      Icon(Icons.my_location, color: _accentColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: pickUpTextEditingController,
                          focusNode: pickUpFocusNode,
                          style: GoogleFonts.poppins(color: _textColor),
                          decoration: InputDecoration(
                            hintText: "PickUp Location",
                            hintStyle: GoogleFonts.poppins(color: _hintColor),
                            fillColor: _inputColor,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          onChanged: (text) {
                            searchPlace(text);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Drop Off Row
                  Row(
                    children: [
                      Icon(Icons.location_on,
                          color: Colors.redAccent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: dropOffTextEditingController,
                          focusNode: dropOffFocusNode,
                          style: GoogleFonts.poppins(color: _textColor),
                          decoration: InputDecoration(
                            hintText: "Where to?",
                            hintStyle: GoogleFonts.poppins(color: _hintColor),
                            fillColor: _inputColor,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                          onChanged: (text) {
                            searchPlace(text);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Prediction List (Placeholder)
            // Prediction List
            Expanded(
              child: ListView.separated(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: placePredictionList.length,
                physics: const ClampingScrollPhysics(),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque, // Catch all taps
                    onTap: () async {
                      // Dismiss Keyboard immediately
                      FocusScope.of(context).unfocus();

                      // Show Loading Dialog
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (c) => Center(
                          child: CircularProgressIndicator(
                            color: _accentColor,
                          ),
                        ),
                      );

                      // 1. Get Place ID
                      String placeId = placePredictionList[index].placeId!;

                      // 2. Get Details (Lat/Lng)
                      var details =
                          await CommonMethods.getPlaceDetails(placeId);

                      // Close Loading Dialog
                      Navigator.pop(context);

                      if (details != null) {
                        var location = details["location"];
                        var lat = location["latitude"];
                        var lng = location["longitude"];

                        if (isPickupFocused) {
                          setState(() {
                            pickUpTextEditingController.text =
                                placePredictionList[index].mainText!;
                            pickupLat = lat;
                            pickupLng = lng;
                            placePredictionList.clear();
                          });
                          // Delay slightly to allow UI update before focus change if needed
                          dropOffFocusNode.requestFocus();
                        } else {
                          setState(() {
                            dropOffTextEditingController.text =
                                placePredictionList[index].mainText!;
                            dropoffLat = lat;
                            dropoffLng = lng;
                          });

                          Map<String, dynamic> responseMap = {
                            "img": "ignored",
                          };

                          if (pickupLat != null && pickupLng != null) {
                            responseMap["pickup"] = {
                              "lat": pickupLat,
                              "lng": pickupLng,
                              "address": pickUpTextEditingController.text,
                            };
                          }

                          if (dropoffLat != null && dropoffLng != null) {
                            responseMap["dropoff"] = {
                              "lat": dropoffLat,
                              "lng": dropoffLng,
                              "address": dropOffTextEditingController.text,
                            };
                          }
                          Navigator.pop(context, responseMap);
                        }
                      } else {
                        // print("DEBUG: details returned NULL from getPlaceDetails");
                      }
                    },
                    child: PlacePredictionTileDesign(
                      placePrediction: placePredictionList[index],
                    ),
                  );
                },
                separatorBuilder: (BuildContext context, int index) {
                  return Divider(
                    height: 0,
                    color: Colors.white10,
                    thickness: 0.5,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void searchPlace(String text) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 1000), () async {
      if (text.length > 2) {
        var res = await CommonMethods.searchPlace(text);
        setState(() {
          placePredictionList = res;
        });
      }
    });
  }
}

class PlacePredictionTileDesign extends StatelessWidget {
  final PlacePrediction placePrediction;

  const PlacePredictionTileDesign({super.key, required this.placePrediction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          const Icon(
            Icons.location_on,
            color: Colors.grey,
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placePrediction.mainText ?? "",
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  placePrediction.secondaryText ?? "",
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
