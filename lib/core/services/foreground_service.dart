import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mobile_app/core/services/foreground_task_handler.dart';
import 'package:mobile_app/core/utils/logger.dart';

// TaskHandler and startCallback moved to foreground_task_handler.dart

class ForegroundServiceWrapper {
  static Future<void> init() async {
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
        eventAction: ForegroundTaskEventAction.repeat(
          5000,
        ), // 5s heartbeat for near-instant relay
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: false,
      ),
    );
  }

  static Future<bool> start({
    required String url,
    required String token,
    String? deviceId,
  }) async {
    try {
      await FlutterForegroundTask.saveData(key: 'backend_url', value: url);
      await FlutterForegroundTask.saveData(key: 'access_token', value: token);
      if (deviceId != null) {
        await FlutterForegroundTask.saveData(key: 'device_id', value: deviceId);
      }

      final NotificationPermission permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        final result =
            await FlutterForegroundTask.requestNotificationPermission();
        if (result != NotificationPermission.granted) {
          return false;
        }
      }

      final bool batteryOptimized =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (!batteryOptimized) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        await FlutterForegroundTask.stopService();
        await Future.delayed(const Duration(milliseconds: 500));
      }

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
        // Log to crashlytics or silent analytics if needed
      } else {
        _triggerManualUpdate();
      }

      return true;
    } catch (e) {
      AppLogger.error('ForegroundServiceWrapper: Failed to start', e);
      return false;
    }
  }

  static Future<void> stop() async {
    await FlutterForegroundTask.stopService();
  }

  static Future<void> openBatterySettings() async {
    await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
  }

  static void _triggerManualUpdate() {
    () async {
      try {
        final url = await FlutterForegroundTask.getData<String>(
          key: 'backend_url',
        );
        final token = await FlutterForegroundTask.getData<String>(
          key: 'access_token',
        );

        if (url == null || token == null) return;

        final response = await http
            .get(
              Uri.parse('$url/api/v1/mobile/mobile-summary'),
              headers: {'Authorization': 'Bearer $token'},
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final today = (data['today_total'] ?? 0.0).toStringAsFixed(0);
          final month = (data['monthly_total'] ?? 0.0).toStringAsFixed(0);

          final rawCurrency = data['currency'] ?? 'INR';
          final currency = rawCurrency == 'INR' ? '₹' : rawCurrency;

          final time = DateTime.now();
          final timeStr =
              "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

          await FlutterForegroundTask.updateService(
            notificationTitle: 'WealthFam Guard',
            notificationText:
                'Spending: $currency$today (Today) • $currency$month (Month)\nLast Updated: $timeStr',
          );
        }
      } catch (e) {
        AppLogger.warn('ForegroundServiceWrapper: Manual update failed: $e');
      }
    }();
  }
}
