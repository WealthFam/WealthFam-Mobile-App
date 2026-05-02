import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

const String updateTaskName = 'wealthfam_stats_update';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('WorkManager: Task started - $task');

    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('backend_url');
      final token = prefs.getString('access_token');

      if (url == null || token == null) {
        debugPrint('WorkManager: Missing credentials');
        return Future.value(true);
      }

      final response = await http
          .get(
            Uri.parse('$url/api/v1/mobile/mobile-summary'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('WorkManager: Data fetched for background refresh');
        // We don't show ID 999 here anymore. The Foreground Service handles it.
      }
    } catch (e) {
      debugPrint('WorkManager: Error - $e');
    }

    return Future.value(true);
  });
}

class NotificationService extends ChangeNotifier {
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> get history => _history;

  int get unreadCount => _history.where((item) => item['isRead'] == false).length;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    debugPrint('NotificationService: Initializing...');

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('ic_notification');
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    try {
      await _notifications.initialize(settings);
    } catch (e) {
      debugPrint('NotificationService: Native notification init failed (expected in tests): $e');
    }
    
    await _loadHistory();

    try {
      // Initialize workmanager
      await Workmanager().initialize(callbackDispatcher);
    } catch (e) {
      debugPrint('NotificationService: Workmanager init failed (expected in tests): $e');
    }

    debugPrint('NotificationService: Initialized');
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('notification_history');
    if (data != null) {
      _history = List<Map<String, dynamic>>.from(
        (jsonDecode(data) as List).cast<Map<String, dynamic>>(),
      );
    }
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notification_history', jsonEncode(_history));
  }

  Future<void> addToHistory(String title, String body, {String type = 'system'}) async {
    _history.insert(0, {
      'title': title,
      'body': body,
      'timestamp': DateTime.now().toIso8601String(),
      'isRead': false,
      'type': type,
    });
    if (_history.length > 50) _history.removeLast();
    await _saveHistory();
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    for (var item in _history) {
      item['isRead'] = true;
    }
    await _saveHistory();
    notifyListeners();
  }

  Future<void> showNotification(int id, String title, String body) async {
    await addToHistory(title, body);

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'wealthfam_main',
      'Main Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    try {
      await _notifications.show(
        id,
        title,
        body,
        platformChannelSpecifics,
      );
    } catch (e) {
      debugPrint('NotificationService: Failed to show system notification: $e');
    }
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  Future<bool> start({required String url, required String token}) async {
    debugPrint('NotificationService: Starting persistent notification');

    try {
      // Save credentials to SharedPreferences for background access
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('backend_url', url);
      await prefs.setString('access_token', token);

      debugPrint('NotificationService: Sync channel initialized');

      // Register periodic task - runs every 15 minutes
      await Workmanager().registerPeriodicTask(
        'wealthfam_stats',
        updateTaskName,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(seconds: 5),
        constraints: Constraints(networkType: NetworkType.connected),
      );

      debugPrint('NotificationService: Started successfully');

      // Trigger immediate update to show real data
      Future.delayed(const Duration(seconds: 3), () {
        debugPrint('NotificationService: Triggering immediate update');
        updateNow(url: url, token: token);
      });

      return true;
    } catch (e, stack) {
      debugPrint('NotificationService: Error starting - $e');
      debugPrint('Stack: $stack');
      return false;
    }
  }

  Future<void> stop() async {
    debugPrint('NotificationService: Stopping');
    await Workmanager().cancelByUniqueName('wealthfam_stats');
    await _notifications.cancel(999);
  }

  Future<void> updateNow({required String url, required String token}) async {
    debugPrint('NotificationService: updateNow called with url=$url');
    try {
      final response = await http
          .get(
            Uri.parse('$url/api/v1/mobile/mobile-summary'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('NotificationService: Response status=${response.statusCode}');
      if (response.statusCode == 200) {
        debugPrint(
          'NotificationService: Manual update successful (data will follow via Foreground task)',
        );
      }
    } catch (e) {
      debugPrint('NotificationService: Update failed - $e');
    }
  }
}
