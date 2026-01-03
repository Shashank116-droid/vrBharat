import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jinete_driver_app/pages/earnings_screen.dart';
import 'package:jinete_driver_app/pages/home_page.dart';
import 'package:jinete_driver_app/pages/profile_screen.dart';
import 'package:jinete_driver_app/pages/trips_page.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with SingleTickerProviderStateMixin {
  TabController? controller;
  int indexSelected = 0;

  @override
  void initState() {
    super.initState();
    controller = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    controller!.dispose();
    super.dispose();
  }

  void onBarItemClicked(int index) {
    setState(() {
      indexSelected = index;
      controller!.index = indexSelected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TabBarView(
        physics: const NeverScrollableScrollPhysics(),
        controller: controller,
        children: const [
          HomePage(),
          EarningsScreen(),
          TripsPage(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
            icon: Icon(Icons.currency_rupee),
            label: "Earnings",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Trips"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
        currentIndex: indexSelected,
        unselectedItemColor: Colors.grey,
        selectedItemColor: const Color(0xFFFF6B00),
        showUnselectedLabels: true,
        selectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF101015),
        onTap: onBarItemClicked,
      ),
    );
  }
}
