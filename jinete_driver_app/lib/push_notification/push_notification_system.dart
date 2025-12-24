import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:jinete_driver_app/global/global_var.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationSystem {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initializeNotification() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  static Future<void> showNotification(String title, String body) async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          'channel_id_driver',
          'Ride Updates',
          channelDescription: 'Notifications about your ride status',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
      payload: 'item x',
    );
  }

  static StreamSubscription<DocumentSnapshot> listenForNewRide(
    BuildContext context,
  ) {
    String driverId = FirebaseAuth.instance.currentUser!.uid;

    return FirebaseFirestore.instance
        .collection("online_drivers")
        .doc(driverId)
        .snapshots()
        .listen((DocumentSnapshot snapshot) {
          if (snapshot.exists) {
            Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
            String rideRequestId = data["newRideStatus"] ?? "idle";

            print("Snapshot New Ride Status :: $rideRequestId");

            if (rideRequestId != "idle") {
              print("Fetching details for rideRequestId: $rideRequestId");

              FirebaseFirestore.instance
                  .collection("rideRequests")
                  .doc(rideRequestId)
                  .get()
                  .then((snap) {
                    if (!context.mounted) return;

                    if (snap.exists) {
                      try {
                        Map<String, dynamic> rideData =
                            snap.data() as Map<String, dynamic>;

                        double pickupLat = double.parse(
                          rideData["pickup"]["latitude"].toString(),
                        );
                        double pickupLng = double.parse(
                          rideData["pickup"]["longitude"].toString(),
                        );

                        // Check Route Logic
                        bool isNearRoute = true;

                        if (driverTripRequestRoute.isNotEmpty) {
                          isNearRoute = false;
                          for (LatLng point in driverTripRequestRoute) {
                            double distance = Geolocator.distanceBetween(
                              pickupLat,
                              pickupLng,
                              point.latitude,
                              point.longitude,
                            );

                            if (distance < 2000) {
                              isNearRoute = true;
                              break;
                            }
                          }
                        }

                        if (isNearRoute) {
                          print(
                            "DEBUG: Ride matched route (or no route set). Playing ringtone.",
                          );
                          FlutterRingtonePlayer().playNotification();
                          // Dialog removed. Requests are shown in Trips Page.
                        } else {
                          print("DEBUG: Ride SILENCED. Too far from route.");
                        }
                      } catch (e) {
                        print("Error parsing ride details: $e");
                      }
                    } else {
                      print(
                        "Ride details snapshot is null for ID: $rideRequestId",
                      );
                    }
                  })
                  .catchError((error) {
                    print("Error fetching ride details: $error");
                  });
            }
          }
        });
  }
}
