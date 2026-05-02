import 'package:flutter/material.dart';

class NavigationProvider extends ChangeNotifier {
  int _selectedIndex = 1; // Dashboard

  int get selectedIndex => _selectedIndex;

  void setTab(int index) {
    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  void switchToDashboard() => setTab(1);
  void switchToInsights() => setTab(0);
  void switchToMutualFunds() => setTab(2);
}
