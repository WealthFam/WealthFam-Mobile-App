import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GoalsService extends ChangeNotifier {
  final AppConfig _config;
  final AuthService _auth;

  List<dynamic> _goals = [];
  List<dynamic> _expenseGroups = [];
  bool _isLoading = false;

  String? _error;

  List<dynamic> get goals => _goals;
  List<dynamic> get expenseGroups => _expenseGroups;
  bool get isLoading => _isLoading;
  String? get error => _error;

  GoalsService(this._config, this._auth) {
    _loadCache();
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedGoals = prefs.getString('cached_goals');
      final cachedGroups = prefs.getString('cached_expense_groups');

      if (cachedGoals != null) {
        _goals = jsonDecode(cachedGoals);
      }
      if (cachedGroups != null) {
        _expenseGroups = jsonDecode(cachedGroups);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('GoalsService: Error loading cache: $e');
    }
  }

  Future<void> _saveGoalsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_goals', jsonEncode(_goals));
    } catch (e) {
      debugPrint('GoalsService: Error saving goals cache: $e');
    }
  }

  Future<void> _saveGroupsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'cached_expense_groups',
        jsonEncode(_expenseGroups),
      );
    } catch (e) {
      debugPrint('GoalsService: Error saving groups cache: $e');
    }
  }

  Future<void> fetchGoals() async {
    if (_auth.accessToken == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final url = '${_config.backendUrl}/api/v1/mobile/investment-goals';
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        _goals = decoded is List ? decoded : [];
        _error = null;
        await _saveGoalsCache();
      } else {
        _error = 'Failed to load: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('Goals Fetch Error: $e');
      _error = 'Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchGoalDetails(String id) async {
    try {
      final response = await http.get(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/investment-goals/$id'),
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final index = _goals.indexWhere((g) => g['id'].toString() == id);
        if (index != -1) {
          _goals[index] = decoded;
        } else {
          _goals.add(decoded);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Goal Details Fetch Error: $e');
    }
  }

  Future<void> fetchExpenseGroups() async {
    if (_auth.accessToken == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/expense-groups'),
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        _expenseGroups = decoded is List ? decoded : [];
        _error = null;
        await _saveGroupsCache();
      } else {
        _error = 'Failed to load expense groups: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('Expense Groups Fetch Error: $e');
      _error = 'Connection error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createGoal(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/investment-goals'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchGoals();
        return true;
      }
    } catch (e) {
      debugPrint('Create Goal Error: $e');
    }
    return false;
  }

  Future<bool> updateGoal(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/investment-goals/$id'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        await fetchGoals();
        return true;
      }
    } catch (e) {
      debugPrint('Update Goal Error: $e');
    }
    return false;
  }

  Future<bool> deleteGoal(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/investment-goals/$id'),
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        await fetchGoals();
        return true;
      }
    } catch (e) {
      debugPrint('Delete Goal Error: $e');
    }
    return false;
  }

  Future<bool> createExpenseGroup(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/expense-groups'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        await fetchExpenseGroups();
        return true;
      }
    } catch (e) {
      debugPrint('Create Expense Group Error: $e');
    }
    return false;
  }

  Future<bool> updateExpenseGroup(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/expense-groups/$id'),
        headers: {
          'Authorization': 'Bearer ${_auth.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        await fetchExpenseGroups();
        return true;
      }
    } catch (e) {
      debugPrint('Update Expense Group Error: $e');
    }
    return false;
  }

  Future<bool> deleteExpenseGroup(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('${_config.backendUrl}/api/v1/mobile/expense-groups/$id'),
        headers: {'Authorization': 'Bearer ${_auth.accessToken}'},
      );
      if (response.statusCode == 200) {
        await fetchExpenseGroups();
        return true;
      }
    } catch (e) {
      debugPrint('Delete Expense Group Error: $e');
    }
    return false;
  }
}
