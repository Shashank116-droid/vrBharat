import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:jinete_driver_app/widgets/loading_dialog.dart';
import 'driver_document_upload_screen.dart';

class VehicleInfoScreen extends StatefulWidget {
  final String driverId;

  const VehicleInfoScreen({super.key, required this.driverId});

  @override
  State<VehicleInfoScreen> createState() => _VehicleInfoScreenState();
}

class _VehicleInfoScreenState extends State<VehicleInfoScreen> {
  String? selectedVehicleType;

  // Design Colors
  final Color _backgroundColor = const Color(0xFF101015);
  final Color _cardColor = const Color(0xFF181820);
  final Color _accentColor = const Color(0xFFFF6B00);
  final Color _textColor = Colors.white;
  final Color _hintColor = Colors.white54;
  final Color _inputColor = const Color(0xFF252530);

  TextEditingController carModelController = TextEditingController();
  TextEditingController carNumberController = TextEditingController();

  

  void saveVehicleInfo() {
    if (selectedVehicleType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a vehicle type.")),
      );
      return;
    }
    if (carModelController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please provide Vehicle Model.")),
      );
      return;
    }
    if (carNumberController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please provide Vehicle Number.")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          LoadingDialog(messageText: "Saving Vehicle Info..."),
    );

    // Save vehicle type and vehicle details structure
    Map<String, Object> vehicleInfo = {
      "type": selectedVehicleType!,
      "model": carModelController.text.trim(),
      "number": carNumberController.text.trim(),
    };

    FirebaseFirestore.instance
        .collection("drivers")
        .doc(widget.driverId)
        .update({"vehicleDetails": vehicleInfo})
        .then((_) {
          if (context.mounted) {
            Navigator.pop(context); // Dismiss loading
            // Navigate to Document Upload Screen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (c) =>
                    DriverDocumentUploadScreen(driverId: widget.driverId),
              ),
            );
          }
        })
        .catchError((error) {
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Error: ${error.toString()}")),
            );
          }
        });
  }

  Widget _buildVehicleCard(String title, String imagePath, String typeValue) {
    bool isSelected = selectedVehicleType == typeValue;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedVehicleType = typeValue;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        width: double.infinity,
        height: 100, // Fixed height for consistency
        decoration: BoxDecoration(
          color: isSelected ? _accentColor.withOpacity(0.2) : _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _accentColor : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 20),
            // Placeholder Icon if image not available, user can replace later
            Icon(_getIconForType(typeValue), color: _textColor, size: 40),
            const SizedBox(width: 20),
            Text(
              title,
              style: GoogleFonts.poppins(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: Icon(Icons.check_circle, color: _accentColor),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case "Car":
        return Icons.directions_car;
      case "Bike":
        return Icons.two_wheeler;
      case "Electric":
        return Icons.electric_car;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                "Select Your Vehicle",
                style: GoogleFonts.poppins(
                  color: _textColor,
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                "Choose the type of vehicle you will be driving.",
                style: GoogleFonts.poppins(color: _hintColor, fontSize: 14),
              ),
              const SizedBox(height: 40),

              _buildVehicleCard("Car", "", "Car"),
              _buildVehicleCard("Bike", "", "Bike"),
              _buildVehicleCard("Electric Vehicle", "", "Electric"),

              const SizedBox(height: 30),

              // Car Model Input
              TextField(
                controller: carModelController,
                style: GoogleFonts.poppins(color: _textColor),
                decoration: InputDecoration(
                  labelText: "Vehicle Model",
                  labelStyle: GoogleFonts.poppins(color: _hintColor),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _hintColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _accentColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: _inputColor,
                ),
              ),

              const SizedBox(height: 20),

              // Car Number Input
              TextField(
                controller: carNumberController,
                style: GoogleFonts.poppins(color: _textColor),
                decoration: InputDecoration(
                  labelText: "License Plate Number",
                  labelStyle: GoogleFonts.poppins(color: _hintColor),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _hintColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: _accentColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: _inputColor,
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: saveVehicleInfo,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    "Continue",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
