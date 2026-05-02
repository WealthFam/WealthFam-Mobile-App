import 'dart:async';
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/errors/either.dart';
import 'package:mobile_app/core/errors/failures.dart';
import 'package:mobile_app/core/utils/logger.dart';
import 'package:mobile_app/core/utils/network_resilience.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/dashboard_data.dart';
import 'package:mobile_app/modules/home/models/unparsed_message.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardService extends ChangeNotifier with NetworkResilience {

  DashboardService(this._config, this._auth) {
    var now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;
    refreshMembers();
    loadSettings();
  }
  final AppConfig _config;
  final AuthService _auth;

  static DashboardService of(BuildContext context, {bool listen = true}) {
    return Provider.of<DashboardService>(context, listen: listen);
  }

  DashboardData? _data;
  bool _isLoading = false;
  String? _error;

  DashboardData? get data => _data;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<dynamic> _members = [];
  String? _selectedMemberId;
  int? _selectedMonth;
  int? _selectedYear;

  // Masking
  double _maskingFactor = 1.0;
  double get maskingFactor => _maskingFactor;

  List<dynamic> get members => _members;
  String? get selectedMemberId => _selectedMemberId;
  int? get selectedMonth => _selectedMonth;
  int? get selectedYear => _selectedYear;

  String get currencySymbol {
    final c = _data?.summary.currency ?? 'INR';
    return c == 'INR' ? '₹' : c;
  }

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _maskingFactor = prefs.getDouble('masking_factor') ?? 1.0;

      // Load existing cache using the consistent key
      // This ensures data is present before refresh() or error screen can hide it
      await _loadCache();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setMaskingFactor(double value) async {
    _maskingFactor = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('masking_factor', value);

    // Sync to foreground task if running
    await _syncMaskingToForeground(value);

    notifyListeners();
  }

  Future<void> toggleMasking() async {
    if (_maskingFactor > 1.0) {
      await setMaskingFactor(1.0);
    } else {
      await setMaskingFactor(100000.0);
    }
  }

  Future<void> _syncMaskingToForeground(double value) async {
    try {
      await FlutterForegroundTask.saveData(key: 'masking_factor', value: value);
    } catch (e) {
      AppLogger.warn('DashboardService: Failed to sync masking to FG: $e');
    }
  }

  void updateMaskingFromForeground(double value) {
    _maskingFactor = value;
    notifyListeners();
  }

  String get _cacheKey =>
      'dashboard_cache_${_selectedYear}_${_selectedMonth}_${_selectedMemberId ?? 'all'}';

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson != null) {
        _data = DashboardData.fromJson(jsonDecode(cachedJson) as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error('DashboardService: Error loading cache', e);
    }
  }

  Future<void> _saveCache() async {
    try {
      if (_data != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(_data!.toJson()));
      }
    } catch (e) {
      AppLogger.error('DashboardService: Error saving cache', e);
    }
  }

  void setMonth(int month, int year) {
    if (_selectedMonth == month && _selectedYear == year) return;
    _selectedMonth = month;
    _selectedYear = year;
    _loadCache(); // Load immediately
    refresh();
  }

  void setMember(String? memberId) {
    if (_selectedMemberId == memberId) return;
    _selectedMemberId = memberId;
    _loadCache(); // Load immediately
    refresh();
  }

  Future<void> refreshMembers() async {
    if (_auth.accessToken == null) return;

    final result = await callWithResilience<List<dynamic>>(
      call: () => http.get(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/members'),
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      ),
      onSuccess: (body) => jsonDecode(body as String) as List<dynamic>,
    );

    result.fold(
      (failure) => AppLogger.warn('Members fetch failure: ${failure.message}'),
      (members) {
        _members = members;
        notifyListeners();
      },
    );
  }

  Future<void> refresh() async {
    if (_auth.accessToken == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    final List<Future<void>> futures = [
      _fetchDashboardSummary(),
      _fetchDashboardTrends(),
      _fetchDashboardCategories(),
      _fetchDashboardInvestments(),
      _fetchCalendarHeatmap(),
    ];

    try {
      if (_members.isEmpty) {
        futures.add(refreshMembers());
      }

      await Future.wait(futures).timeout(const Duration(seconds: 20));
      _error = null;
    } catch (e) {
      AppLogger.error('Dashboard Service Multi-Fetch Failure', e);
      if (e is TimeoutException) {
        _error = 'Dashboard update timed out';
      } else {
        _error = 'Failed to sync some data';
      }
    } finally {
      _isLoading = false;
      await _saveCache();
      notifyListeners();
    }
  }

  Future<void> _fetchDashboardSummary() async {
    final result = await callWithResilience<Map<String, dynamic>>(
      call: () => http.get(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/dashboard/summary',
        ).replace(queryParameters: _getQueryParams()),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => jsonDecode(body as String) as Map<String, dynamic>,
    );

    result.fold((failure) => _error = failure.message, (data) {
      final summary = DashboardSummary.fromJson(data['summary'] as Map<String, dynamic>);
      final budget = BudgetSummary.fromJson(data['budget'] as Map<String, dynamic>);
      final txns = (data['recent_transactions'] as List)
          .map((i) => RecentTransaction.fromJson(i as Map<String, dynamic>))
          .where((t) => !t.isHidden)
          .toList();

      _updateData(
        (d) => d.copyWith(
          summary: summary,
          budget: budget,
          recentTransactions: txns,
          pendingTriageCount: (data['pending_triage_count'] as num?)?.toInt(),
          pendingTrainingCount: (data['pending_training_count'] as num?)?.toInt() ?? 0,
          familyMembersCount: (data['family_members_count'] as num?)?.toInt(),
        ),
      );
    });
  }

  Future<void> _fetchDashboardTrends() async {
    final result = await callWithResilience<Map<String, dynamic>>(
      call: () => http.get(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/dashboard/trends',
        ).replace(queryParameters: _getQueryParams()),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => jsonDecode(body as String) as Map<String, dynamic>,
    );

    result.fold((failure) => _error = failure.message, (data) {
      final spendingTrend = (data['spending_trend'] as List)
          .map((i) => SpendingTrendItem.fromJson(i as Map<String, dynamic>))
          .toList();
      final monthWiseTrend = (data['month_wise_trend'] as List)
          .map((i) => MonthTrendItem.fromJson(i as Map<String, dynamic>))
          .toList();

      _updateData(
        (d) => d.copyWith(
          spendingTrend: spendingTrend,
          monthWiseTrend: monthWiseTrend,
        ),
      );
    });
  }

  Future<void> _fetchDashboardCategories() async {
    final result = await callWithResilience<Map<String, dynamic>>(
      call: () => http.get(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/dashboard/categories',
        ).replace(queryParameters: _getQueryParams()),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => jsonDecode(body as String) as Map<String, dynamic>,
    );

    result.fold((failure) => _error = failure.message, (data) {
      final categories = (data['category_distribution'] as List)
          .map((i) => CategoryPieItem.fromJson(i as Map<String, dynamic>))
          .toList();

      _updateData((d) => d.copyWith(categoryDistribution: categories));
    });
  }

  Future<void> _fetchDashboardInvestments() async {
    final result = await callWithResilience<Map<String, dynamic>>(
      call: () => http.get(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/dashboard/investments',
        ).replace(queryParameters: _getQueryParams()),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => jsonDecode(body as String) as Map<String, dynamic>,
    );

    result.fold((failure) => _error = failure.message, (data) {
      InvestmentSummary? investmentSummary;
      if (data['investment_summary'] != null) {
        investmentSummary = InvestmentSummary.fromJson(
          data['investment_summary'] as Map<String, dynamic>,
        );
      }
      _updateData((d) => d.copyWith(investmentSummary: investmentSummary));
    });
  }

  Future<void> _fetchCalendarHeatmap() async {
    final result = await callWithResilience<Map<String, dynamic>>(
      call: () => http.get(
        Uri.parse(
          '${_config.backendUrl}/api/v1/mobile/heatmap/calendar',
        ).replace(queryParameters: _getQueryParams()),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => jsonDecode(body as String) as Map<String, dynamic>,
    );

    result.fold((failure) => _error = failure.message, (data) {
      final heatmapData = data;
      final Map<String, Decimal> heatmap = heatmapData.map(
        (k, v) => MapEntry(k, Decimal.parse(v.toString())),
      );
      _updateData((d) => d.copyWith(calendarHeatmap: heatmap));
    });
  }

  Future<Either<Failure, List<UnparsedMessage>>> fetchTrainingQueue({
    String? search,
  }) async {
    return callWithResilience<List<UnparsedMessage>>(
      call: () => http.get(
        Uri.parse('${_config.backendUrl}/api/v1/ingestion/training').replace(
          queryParameters: {
            if (search != null && search.isNotEmpty) 'search': search,
          },
        ),
        headers: _getHeaders(),
      ),
onSuccess: (body) {
        final data = jsonDecode(body as String) as Map<String, dynamic>;
        final items = data['data'] as List? ?? [];
        return items.map((i) => UnparsedMessage.fromJson(i as Map<String, dynamic>)).toList();
      },
    );
  }

  Future<Either<Failure, Unit>> finalizeTraining({
    required String messageId,
    required DateTime date,
    required String description,
    required Decimal amount,
    required String category,
    String? accountId,
    String? accountMask,
    String type = 'DEBIT',
    bool createRule = true,
    bool applyToUnparsed = true,
  }) async {
    return callWithResilience<Unit>(
      call: () => http.post(
        Uri.parse(
          '${_config.backendUrl}/api/v1/ingestion/training/$messageId/label',
        ),
        headers: _getHeaders(),
        body: jsonEncode({
          'date': date.toUtc().toIso8601String(),
          'recipient': description,
          'amount': amount,
          'category': category,
          'account_id': accountId,
          'account_mask': accountMask,
          'type': type,
          'generate_pattern': createRule,
          'apply_to_unparsed': applyToUnparsed,
        }),
      ),
      onSuccess: (_) => unit,
    );
  }

  Future<Either<Failure, List<dynamic>>> fetchAccounts() async {
    return callWithResilience<List<dynamic>>(
      call: () => http.get(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/accounts'),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => (jsonDecode(body as String) as Map<String, dynamic>)['data'] as List<dynamic>,
    );
  }

  Future<Either<Failure, Unit>> dismissTraining(String messageId) async {
    return callWithResilience<Unit>(
      call: () => http.post(
        Uri.parse(
          '${_config.backendUrl}/api/v1/ingestion/training/$messageId/dismiss',
        ),
        headers: _getHeaders(),
        body: jsonEncode({'create_rule': false}),
      ),
      onSuccess: (_) => unit,
    );
  }

  Future<Either<Failure, Map<String, dynamic>>> aiForensicParse(
    String content,
  ) async {
    return callWithResilience<Map<String, dynamic>>(
      call: () => http.post(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/ai/forensic-parse'),
        headers: _getHeaders(),
        body: jsonEncode({'content': content}),
      ),
      onSuccess: (body) => jsonDecode(body as String) as Map<String, dynamic>,
    );
  }

  Future<Either<Failure, List<dynamic>>> fetchSpamFilters() async {
    return callWithResilience<List<dynamic>>(
      call: () => http.get(
        Uri.parse('${_config.backendUrl}/api/v1/ingestion/training/spam'),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => (jsonDecode(body as String) as Map<String, dynamic>)['data'] as List<dynamic>? ?? [],
    );
  }

  Future<Either<Failure, Unit>> markAsSpam(String messageId) async {
    return callWithResilience<Unit>(
      call: () => http.post(
        Uri.parse(
          '${_config.backendUrl}/api/v1/ingestion/training/$messageId/mark-as-spam',
        ),
        headers: _getHeaders(),
      ),
      onSuccess: (_) => unit,
    );
  }

  Future<Either<Failure, Unit>> bulkIgnore(List<String> ids) async {
    return callWithResilience<Unit>(
      call: () => http.post(
        Uri.parse(
          '${_config.backendUrl}/api/v1/ingestion/training/bulk-dismiss',
        ),
        headers: _getHeaders(),
        body: jsonEncode({'ids': ids, 'create_rule': false}),
      ),
      onSuccess: (_) => unit,
    );
  }

  Future<Either<Failure, Unit>> deleteSpamFilter(String filterId) async {
    return callWithResilience<Unit>(
      call: () => http.delete(
        Uri.parse(
          '${_config.backendUrl}/api/v1/ingestion/training/spam/$filterId',
        ),
        headers: _getHeaders(),
      ),
      onSuccess: (_) => unit,
    );
  }

  Future<Either<Failure, List<dynamic>>> fetchGeographicalHeatmap({
    int? month,
    int? year,
    String? memberId,
  }) async {
    return callWithResilience<List<dynamic>>(
      call: () => http.get(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/heatmap').replace(
          queryParameters: {
            if (month != null) 'month': month.toString(),
            if (year != null) 'year': year.toString(),
            if (memberId != null) 'member_id': memberId,
          },
        ),
        headers: _getHeaders(),
      ),
      onSuccess: (body) => jsonDecode(body as String) as List<dynamic>,
    );
  }

  void _updateData(DashboardData Function(DashboardData) updater) {
    _data ??= DashboardData(
      summary: DashboardSummary(
        todayTotal: Decimal.zero,
        yesterdayTotal: Decimal.zero,
        lastMonthSameDayTotal: Decimal.zero,
        monthlyTotal: Decimal.zero,
        currency: 'INR',
        dailyBudgetLimit: Decimal.zero,
        proratedBudget: Decimal.zero,
      ),
      budget: BudgetSummary(
        limit: Decimal.zero,
        spent: Decimal.zero,
        percentage: Decimal.zero,
      ),
      spendingTrend: [],
      categoryDistribution: [],
      monthWiseTrend: [],
      recentTransactions: [],
    );
    _data = updater(_data!);
    notifyListeners();
  }

  Map<String, String> _getQueryParams() {
    return {
      if (_selectedMonth != null) 'month': _selectedMonth.toString(),
      if (_selectedYear != null) 'year': _selectedYear.toString(),
      if (_selectedMemberId != null) 'member_id': _selectedMemberId!,
    };
  }

  Map<String, String> _getHeaders() {
    return {
      'Authorization': 'Bearer ${_auth.accessToken}',
      'Content-Type': 'application/json',
    };
  }
}
