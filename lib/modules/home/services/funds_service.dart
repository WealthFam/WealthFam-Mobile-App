import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/models/fund_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FundsService extends ChangeNotifier {

  FundsService(this._config, this._auth) {
    _loadCache();
  }
  final AppConfig _config;
  final AuthService _auth;

  PortfolioSummary? _portfolio;
  bool _isLoading = false;
  String? _error;

  PortfolioSummary? get portfolio => _portfolio;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Sync State
  Map<String, dynamic>? _syncStatus;
  Map<String, dynamic>? get syncStatus => _syncStatus;

  // Filter State
  String? _selectedMemberId;
  String? get selectedMemberId => _selectedMemberId;

  String get _cacheKey => 'cached_portfolio_${_selectedMemberId ?? 'all'}';

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKey);
      if (cachedJson != null) {
        _portfolio = PortfolioSummary.fromJson(jsonDecode(cachedJson) as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('FundsService: Error loading cache: $e');
    }
  }

  Future<void> _saveCache() async {
    try {
      if (_portfolio != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(_portfolio!.toJson()));
      }
    } catch (e) {
      debugPrint('FundsService: Error saving cache: $e');
    }
  }

  void setMember(String? memberId) {
    _selectedMemberId = memberId;
    fetchFunds();
  }

  Future<void> fetchFunds() async {
    if (_auth.accessToken == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final url = Uri.parse('${_config.backendUrl}/api/v1/mobile/funds')
          .replace(
            queryParameters: {
              if (_selectedMemberId != null) 'member_id': _selectedMemberId,
            },
          );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        _portfolio = PortfolioSummary.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
        _error = null;
        await _saveCache();
      } else {
        _error = 'Failed to load funds: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('Funds Error: $e');
      _error = 'Network error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    // Fetch chart data and sync status in background after main data
    fetchPerformance();
    fetchSyncStatus();
  }

  Future<void> fetchSyncStatus() async {
    if (_auth.accessToken == null) return;
    try {
      final url = Uri.parse(
        '${_config.backendUrl}/api/v1/finance/mutual-funds/sync/status',
      );
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        _syncStatus = jsonDecode(response.body) as Map<String, dynamic>;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Sync Status Error: $e');
    }
  }

  Future<void> triggerSync() async {
    if (_auth.accessToken == null) return;
    try {
      final url = Uri.parse(
        '${_config.backendUrl}/api/v1/finance/mutual-funds/sync/refresh',
      );
      final response = await http.post(
        url,
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        await fetchSyncStatus();
      }
    } catch (e) {
      debugPrint('Trigger Sync Error: $e');
    }
  }

  // --- Performance Chart Data ---
  List<Map<String, dynamic>> _timeline = [];
  List<Map<String, dynamic>> get timeline => _timeline;
  bool _isChartLoading = false;
  bool get isChartLoading => _isChartLoading;

  Future<void> fetchPerformance() async {
    if (_auth.accessToken == null) return;

    _isChartLoading = true;
    notifyListeners();

    try {
      final url =
          Uri.parse(
            '${_config.backendUrl}/api/v1/finance/mutual-funds/analytics/performance-timeline',
          ).replace(
            queryParameters: {
              'period': '1y',
              'granularity': '1w',
              if (_selectedMemberId != null) 'user_id': _selectedMemberId,
            },
          );

      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map && data['timeline'] != null) {
          _timeline = List<Map<String, dynamic>>.from(data['timeline'] as Iterable<dynamic>);
        } else if (data is List) {
          _timeline = List<Map<String, dynamic>>.from(data);
        }
      }
    } catch (e) {
      debugPrint('Chart Error: $e');
    } finally {
      _isChartLoading = false;
      notifyListeners();
    }
  }
}
