import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete_driver_app/authentication/login_screen.dart';
import 'package:jinete_driver_app/pages/earnings_screen.dart';
import 'package:jinete_driver_app/pages/profile_screen.dart';
import 'package:jinete_driver_app/pages/trips_history_screen.dart';

class CustomDrawer extends StatelessWidget {
  final String? name;
  final String? phone;

  const CustomDrawer({super.key, this.name, this.phone});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        children: [
          // Drawer Header
          Container(
            height: 165,
            color: Colors.black,
            child: DrawerHeader(
              decoration: const BoxDecoration(color: Colors.black),
              child: Row(
                children: [
                  const Icon(Icons.person, size: 60, color: Colors.white),
                  const SizedBox(width: 16),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name ?? "Driver Name",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        phone ?? "+91 XXXXX XXXXX",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Drawer Body Items
          ListTile(
            leading: const Icon(Icons.history, color: Colors.white54),
            title: Text(
              "History",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context); // Close Drawer
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const TripsHistoryScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.currency_rupee, color: Colors.white54),
            title: Text(
              "Earnings",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const EarningsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.person, color: Colors.white54),
            title: Text(
              "Visit Profile",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context); // Close Drawer
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const ProfileScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info, color: Colors.white54),
            title: Text(
              "About",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            onTap: () {
              // Navigate to About
            },
          ),

          const SizedBox(height: 30),
          const Divider(height: 1, color: Colors.grey, thickness: 1),
          const SizedBox(height: 10),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white54),
            title: Text(
              "Sign Out",
              style: GoogleFonts.poppins(color: Colors.white),
            ),
            onTap: () {
              FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (c) => LoginScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}
