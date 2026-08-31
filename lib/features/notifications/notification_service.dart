import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:smart_fin/features/notifications/notification_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';

@pragma('vm:entry-point')
void notificationCallback(NotificationEvent event) async {
  // This runs in a separate isolate in the background
  print("Background notification received: ${event.title} - ${event.content}");
  
  // We can try to send it to the backend here if it looks like a bank SMS.
  // For simplicity, we send all notifications from specific packages, or just everything for demo.
  final text = "${event.title}: ${event.content}";
  
  // Need to find a way to get the current user ID in the background isolate, 
  // maybe via SharedPreferences or we just send it if we have it.
  // As a fallback, this logic is usually handled better in the foreground stream if the app is alive.
  // For production, we'd use shared_preferences to fetch the saved UID.
}

class NotificationService {
  final NotificationRepository _repository = NotificationRepository();

  Future<void> initialize() async {
    // Check if permission is granted
    bool status = await NotificationListenerService.isPermissionGranted();
    
    if (!status) {
      print("Requesting notification listener permission...");
      status = await NotificationListenerService.requestPermission();
    }
    
    if (status) {
      print("Notification listener permission granted!");
      
      // Listen to incoming notifications while app is running
      NotificationListenerService.notificationsStream.listen((event) {
        print("Foreground notification received: ${event.title} - ${event.content}");
        _processNotification(event);
      });
    } else {
      print("Notification listener permission denied.");
    }
  }

  void _processNotification(NotificationEvent event) {
    // Very basic filter: if it contains typical banking words or if the app is a known banking app.
    // E.g., event.packageName == "com.kasikornbank"
    final text = "${event.title} ${event.content}";
    final lowerText = text.toLowerCase();
    
    if (lowerText.contains("baht") || lowerText.contains("thb") || lowerText.contains("payment") || lowerText.contains("transfer")) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _repository.sendNotificationToBackend(user.uid, text);
      }
    }
  }
}
