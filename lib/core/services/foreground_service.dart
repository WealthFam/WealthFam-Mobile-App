import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mobile_app/core/services/foreground_task_handler.dart';

// TaskHandler and startCallback moved to foreground_task_handler.dart

class ForegroundServiceWrapper {
  static Future<void> init() async {
    debugPrint("ForegroundService: Initializing...");
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wealthfam_fg_sync',
        channelName: 'WealthFam Guard',
        channelDescription: 'Live spending tracker and SMS sync',
        channelImportance: NotificationChannelImportance.HIGH, 
        priority: NotificationPriority.HIGH,
        playSound: false,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_PUBLIC,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(600000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: false,
      ),
    );
    debugPrint("ForegroundService: Init complete");
  }

  static Future<bool> start({required String url, required String token}) async {
    debugPrint("ForegroundService: Start Requested");
    
    try {
      await FlutterForegroundTask.saveData(key: 'backend_url', value: url);
      await FlutterForegroundTask.saveData(key: 'access_token', value: token);

      final NotificationPermission permission = await FlutterForegroundTask.checkNotificationPermission();
      if(permission != NotificationPermission.granted) {
        final result = await FlutterForegroundTask.requestNotificationPermission();
        if (result != NotificationPermission.granted) {
          debugPrint("ForegroundService: Notification permission denied");
          return false;
        }
      }

      final bool batteryOptimized = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!batteryOptimized) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        debugPrint("ForegroundService: Restarting existing service");
        await FlutterForegroundTask.restartService();
        _triggerManualUpdate();
        return true;
      }

      debugPrint("ForegroundService: Starting new service");
      final result = await FlutterForegroundTask.startService(
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'WealthFam Guard',
        notificationText: 'Initializing tracker...',
        notificationIcon: const NotificationIcon(
          metaDataName: 'com.wealthfam.notification_icon',
        ),
        notificationButtons: [
          const NotificationButton(id: 'toggle_mask', text: 'Toggle Mask'),
          const NotificationButton(id: 'refresh', text: 'Refresh'),
        ],
        callback: startCallback,
      );
      
      if (result is ServiceRequestFailure) {
        debugPrint("ForegroundService: Start failed: ${result.error}");
      } else {
        debugPrint("ForegroundService: Start success");
        _triggerManualUpdate();
      }
      
      return true;
    } catch (e) {
      debugPrint("ForegroundService: Exception: $e");
      return false;
    }
  }

  static Future<void> stop() async {
    debugPrint("ForegroundService: Stopping service");
    await FlutterForegroundTask.stopService();
  }

  static Future<void> openBatterySettings() async {
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  }
  
  static void _triggerManualUpdate() {
    () async {
      try {
        final url = await FlutterForegroundTask.getData<String>(key: 'backend_url');
        final token = await FlutterForegroundTask.getData<String>(key: 'access_token');
        
        if (url == null || token == null) return;

        final response = await http.get(
          Uri.parse('$url/api/v1/mobile/mobile-summary'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final today = (data['today_total'] ?? 0.0).toStringAsFixed(0);
          final month = (data['monthly_total'] ?? 0.0).toStringAsFixed(0);
          
          final rawCurrency = data['currency'] ?? 'INR';
          final currency = rawCurrency == 'INR' ? '₹' : rawCurrency;

          final time = DateTime.now();
          final timeStr = "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

          await FlutterForegroundTask.updateService(
            notificationTitle: 'WealthFam Guard',
            notificationText: 'Spending: $currency$today (Today) • $currency$month (Month)\nLast Updated: $timeStr',
          );
          debugPrint("ForegroundService: Initial update complete");
        }
      } catch (e) {
        debugPrint("ForegroundService: Initial update failed: $e");
      }
    }();
  }
}

