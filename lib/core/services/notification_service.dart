import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const String updateTaskName = "wealthfam_stats_update";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("WorkManager: Task started - $task");
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('backend_url');
      final token = prefs.getString('access_token');
      final maskingFactor = prefs.getDouble('masking_factor') ?? 1.0;
      
      if (url == null || token == null) {
        debugPrint("WorkManager: Missing credentials");
        return Future.value(true);
      }

      final response = await http.get(
        Uri.parse('$url/api/v1/mobile/mobile-summary'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint("WorkManager: Data fetched for background refresh");
        // We don't show ID 999 here anymore. The Foreground Service handles it.
      }
    } catch (e) {
      debugPrint("WorkManager: Error - $e");
    }

    return Future.value(true);
  });
}

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  
  Future<void> init() async {
    debugPrint("NotificationService: Initializing...");
    
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('ic_notification');
    const InitializationSettings settings = InitializationSettings(android: androidSettings);
    
    await _notifications.initialize(settings);
    
    // Initialize workmanager
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: true);
    
    debugPrint("NotificationService: Initialized");
  }

  Future<bool> start({required String url, required String token}) async {
    debugPrint("NotificationService: Starting persistent notification");
    
    try {
      // Save credentials to SharedPreferences for background access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backend_url', url);
      await prefs.setString('access_token', token);
      
      debugPrint("NotificationService: Sync channel initialized");
      
      // Register periodic task - runs every 15 minutes
      await Workmanager().registerPeriodicTask(
        "wealthfam_stats",
        updateTaskName,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(seconds: 5),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );
      
      debugPrint("NotificationService: Started successfully");
      
      // Trigger immediate update to show real data
      Future.delayed(const Duration(seconds: 3), () {
        debugPrint("NotificationService: Triggering immediate update");
        updateNow(url: url, token: token);
      });
      
      return true;
    } catch (e, stack) {
      debugPrint("NotificationService: Error starting - $e");
      debugPrint("Stack: $stack");
      return false;
    }
  }

  Future<void> stop() async {
    debugPrint("NotificationService: Stopping");
    await Workmanager().cancelByUniqueName("wealthfam_stats");
    await _notifications.cancel(999);
  }

  /// Show a one-off notification (e.g. for SMS received events)
  Future<void> showNotification({required String title, required String body, int? id}) async {
    try {
      final int notificationId = id ?? DateTime.now().millisecondsSinceEpoch % 2147483647;
      await _notifications.show(
        notificationId,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'wealthfam_sms',
            'WealthFam SMS Sync',
            channelDescription: 'Notifications for SMS sync events',
            importance: Importance.max,
            priority: Priority.max,
            playSound: true,
            autoCancel: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint("NotificationService.showNotification error: $e");
    }
  }

  Future<void> updateNow({required String url, required String token}) async {
    debugPrint("NotificationService: updateNow called with url=$url");
    try {
      final response = await http.get(
        Uri.parse('$url/api/v1/mobile/mobile-summary'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      debugPrint("NotificationService: Response status=${response.statusCode}");
      if (response.statusCode == 200) {
        debugPrint("NotificationService: Manual update successful (data will follow via Foreground task)");
      }
    } catch (e) {
      debugPrint("NotificationService: Update failed - $e");
    }
  }
}
