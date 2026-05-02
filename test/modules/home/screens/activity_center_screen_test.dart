import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/services/notification_service.dart';
import 'package:mobile_app/modules/home/screens/activity_center_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationService notificationService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    notificationService = NotificationService();
    await notificationService.init();
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: ChangeNotifierProvider<NotificationService>.value(
        value: notificationService,
        child: const ActivityCenterScreen(),
      ),
    );
  }

  testWidgets('ActivityCenterScreen shows empty state when no notifications', (
    tester,
  ) async {
    await tester.pumpWidget(createTestWidget());

    expect(find.text('No recent activity'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
  });

  testWidgets('ActivityCenterScreen shows notification items', (tester) async {
    await notificationService.addToHistory('Test Title', 'Test Body');
    await tester.pumpWidget(createTestWidget());

    expect(find.text('Test Title'), findsOneWidget);
    expect(find.text('Test Body'), findsOneWidget);
    expect(find.text('No recent activity'), findsNothing);
  });

  testWidgets('Clearing notifications from UI works', (tester) async {
    await notificationService.addToHistory('To be cleared', 'Body');
    await tester.pumpWidget(createTestWidget());

    expect(find.text('To be cleared'), findsOneWidget);

    // Tap clear button in AppBar
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle(); // Wait for dialog

    expect(find.text('Clear History'), findsOneWidget);
    
    // Tap Clear in dialog
    await tester.tap(find.text('Clear').last);
    await tester.pumpAndSettle();

    expect(find.text('No recent activity'), findsOneWidget);
    expect(notificationService.history, isEmpty);
  });
}
