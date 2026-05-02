import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationService notificationService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    notificationService = NotificationService();
    await notificationService.init();
  });

  group('NotificationService History Tests', () {
    test('Initial history should be empty', () {
      expect(notificationService.history, isEmpty);
      expect(notificationService.unreadCount, 0);
    });

    test('Adding to history should increase count and set unread', () async {
      await notificationService.addToHistory(
        'Test Title',
        'Test Body',
        type: 'alert',
      );

      expect(notificationService.history.length, 1);
      expect(notificationService.history.first['title'], 'Test Title');
      expect(notificationService.history.first['isRead'], false);
      expect(notificationService.unreadCount, 1);
    });

    test('Marking all as read should reset unread count', () async {
      await notificationService.addToHistory('Title', 'Body');
      expect(notificationService.unreadCount, 1);

      await notificationService.markAllAsRead();
      expect(notificationService.unreadCount, 0);
      expect(notificationService.history.first['isRead'], true);
    });

    test('Clearing history should empty the list', () async {
      await notificationService.addToHistory('Title', 'Body');
      await notificationService.clearHistory();

      expect(notificationService.history, isEmpty);
      expect(notificationService.unreadCount, 0);
    });

    test('History should persist across re-initialization', () async {
      await notificationService.addToHistory('Persistent Title', 'Body');
      
      // Simulate app restart by re-initializing
      final newService = NotificationService();
      await newService.init();
      
      expect(newService.history.length, 1);
      expect(newService.history.first['title'], 'Persistent Title');
    });

    test('History should respect the limit of 50 items', () async {
      for (int i = 0; i < 60; i++) {
        await notificationService.addToHistory('Item $i', 'Body');
      }
      
      expect(notificationService.history.length, 50);
      // Newest items should be at the beginning
      expect(notificationService.history.first['title'], 'Item 59');
    });
   group('showNotification Integration', () {
    test('showNotification should add to history', () async {
      // Note: This won't actually show a system notification in tests easily without more mocks,
      // but it should trigger history addition.
      await notificationService.showNotification(
        1,
        'Notification Title',
        'Notification Body',
      );
      
      expect(notificationService.history.length, 1);
      expect(notificationService.history.first['title'], 'Notification Title');
    });
  });
  });
}
