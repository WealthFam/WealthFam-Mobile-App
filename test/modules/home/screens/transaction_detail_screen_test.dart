import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/screens/transaction_detail_screen.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestDashboardService extends ChangeNotifier implements DashboardService {
  @override
  String get currencySymbol => '₹';
  @override
  double get maskingFactor => 1.0;
  
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  final testTransaction = RecentTransaction(
    id: '123',
    date: DateTime.now(),
    description: 'Test Merchant',
    amount: Decimal.parse('1500.50'),
    category: 'Shopping',
    accountName: 'Primary Bank',
    source: 'SMS',
  );

  late DashboardService mockDashboard;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockDashboard = TestDashboardService();
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: ChangeNotifierProvider<DashboardService>.value(
        value: mockDashboard,
        child: TransactionDetailScreen(transaction: testTransaction),
      ),
    );
  }

  testWidgets('TransactionDetailScreen displays correct information', (
    tester,
  ) async {
    await tester.pumpWidget(createTestWidget());

    expect(find.text('Test Merchant'), findsOneWidget);
    expect(find.textContaining('1,500.50'), findsOneWidget);
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.text('Primary Bank'), findsOneWidget);
    expect(find.text('SMS'), findsOneWidget);
  });

  testWidgets('TransactionDetailScreen timeline contains steps', (tester) async {
    await tester.pumpWidget(createTestWidget());
    
    expect(find.text('Detected'), findsOneWidget);
    expect(find.text('Categorized'), findsOneWidget);
    expect(find.text('Synced'), findsOneWidget);
  });
}
