import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete_driver_app/methods/common_methods.dart';
import 'package:jinete_driver_app/models/place_prediction.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
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
  DateTime? selectedDate; // Scheduling

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

  Future<void> _pickDateTime() async {
    DateTime now = DateTime.now();
    DateTime? d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: _accentColor,
              onPrimary: Colors.white,
              surface: _cardColor,
              onSurface: _textColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (d != null) {
      if (!mounted) return;
      TimeOfDay? t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.dark(
                primary: _accentColor,
                onPrimary: Colors.white,
                surface: _cardColor,
                onSurface: _textColor,
              ),
            ),
            child: child!,
          );
        },
      );

      if (t != null) {
        setState(() {
          selectedDate = DateTime(d.year, d.month, d.day, t.hour, t.minute);
        });
      }
    }
  }

  void searchPlace(String text) {
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
                    "Set Destination",
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
                            hintText: "Pickup Location",
                            hintStyle: GoogleFonts.poppins(color: _hintColor),
                            fillColor: _inputColor,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
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
                      Icon(
                        Icons.location_on,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: dropOffTextEditingController,
                          focusNode: dropOffFocusNode,
                          style: GoogleFonts.poppins(color: _textColor),
                          decoration: InputDecoration(
                            hintText: "Where are you going?",
                            hintStyle: GoogleFonts.poppins(color: _hintColor),
                            fillColor: _inputColor,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
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

            const SizedBox(height: 16),

            // Schedule Button
            GestureDetector(
              onTap: _pickDateTime,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selectedDate != null ? _accentColor : Colors.white10,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month,
                      color: selectedDate != null
                          ? _accentColor
                          : Colors.white54,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        selectedDate == null
                            ? "Schedule for Later (Optional)"
                            : "Scheduled: ${selectedDate.toString().substring(0, 16)}",
                        style: GoogleFonts.poppins(
                          color: selectedDate != null ? _textColor : _hintColor,
                          fontWeight: selectedDate != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (selectedDate != null)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedDate = null;
                          });
                        },
                        child: const Icon(Icons.close, color: Colors.white54),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Prediction List
            Expanded(
              child: ListView.separated(
                itemCount: placePredictionList.length,
                physics: const ClampingScrollPhysics(),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      // Dismiss Keyboard
                      FocusScope.of(context).unfocus();

                      // Show Loading
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (c) => Center(
                          child: CircularProgressIndicator(color: _accentColor),
                        ),
                      );

                      // Get Place Details
                      String placeId = placePredictionList[index].placeId!;
                      var details = await CommonMethods.getPlaceDetails(
                        placeId,
                      );

                      if (!context.mounted) return;
                      Navigator.pop(context); // Close loading

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
                          dropOffFocusNode.requestFocus();
                        } else {
                          setState(() {
                            dropOffTextEditingController.text =
                                placePredictionList[index].mainText!;
                            dropoffLat = lat;
                            dropoffLng = lng;
                          });

                          // Return Result
                          Map<String, dynamic> responseMap = {};

                          if (pickupLat != null && pickupLng != null) {
                            responseMap["pickup"] = {
                              "lat": pickupLat,
                              "lng": pickupLng,
                              "address": pickUpTextEditingController.text,
                            };
                          } else {
                            // Use 'current' if not set
                            responseMap["pickup"] = {
                              "lat": null, // Handle in HomePage
                              "lng": null,
                              "address": "current_location",
                            };
                          }

                          responseMap["dropoff"] = {
                            "lat": dropoffLat,
                            "lng": dropoffLng,
                            "address": dropOffTextEditingController.text,
                          };

                          // Add Schedule Date
                          if (selectedDate != null) {
                            responseMap["tripDate"] =
                                selectedDate!.millisecondsSinceEpoch;
                          }

                          Navigator.pop(context, responseMap);
                        }
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
          const Icon(Icons.location_on, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  placePrediction.mainText ?? "",
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 2),
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
