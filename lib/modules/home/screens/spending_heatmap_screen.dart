import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/core/widgets/app_shell.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';

class SpendingHeatmapScreen extends StatefulWidget {
  const SpendingHeatmapScreen({super.key});

  @override
  State<SpendingHeatmapScreen> createState() => _SpendingHeatmapScreenState();
}

class _SpendingHeatmapScreenState extends State<SpendingHeatmapScreen> {
  List<dynamic> _heatmapData = [];
  List<WeightedLatLng> _weightedPoints = [];
  bool _isLoading = true;
  String? _error;
  late DateTime _startDate;
  late DateTime _endDate;
  final MapController _mapController = MapController();
  final StreamController<void> _rebuildStream = StreamController.broadcast();

  static final Map<double, MaterialColor> _heatGradient = {
    0.25: Colors.blue,
    0.55: Colors.green,
    0.85: Colors.orange,
    1.00: Colors.red,
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchHeatmapData());
  }

  @override
  void dispose() {
    _rebuildStream.close();
    super.dispose();
  }

  Future<void> _fetchHeatmapData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final config = context.read<AppConfig>();
    final auth = context.read<AuthService>();

    try {
      final url = Uri.parse('${config.backendUrl}/api/v1/mobile/heatmap').replace(
        queryParameters: {
          'start_date': _startDate.toIso8601String(),
          'end_date': _endDate.toIso8601String(),
        },
      );

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer ${auth.accessToken}'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final weighted = data.map((p) {
          final lat = (p['latitude'] as num).toDouble();
          final lng = (p['longitude'] as num).toDouble();
          final amt = (p['amount'] as num).toDouble();
          return WeightedLatLng(LatLng(lat, lng), amt);
        }).toList();

        if (mounted) {
          setState(() {
            _heatmapData = data;
            _weightedPoints = weighted;
            _isLoading = false;
          });

          if (weighted.isNotEmpty) {
            _rebuildStream.add(null);
            _fitMapBounds();
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load: ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection error';
          _isLoading = false;
        });
      }
    }
  }

  void _fitMapBounds() {
    if (_heatmapData.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_heatmapData.length == 1) {
        final p = _heatmapData[0];
        _mapController.move(
          LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()),
          14,
        );
      } else {
        final points = _heatmapData.map((p) =>
          LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble())
        ).toList();

        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
        );
      }
    });
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchHeatmapData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = context.read<DashboardService>().currencySymbol;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('Spending Map'),
        actions: [
          ActionChip(
            avatar: const Icon(Icons.calendar_today, size: 16),
            label: Text(
              '${DateFormat('MMM d').format(_startDate)} — ${DateFormat('MMM d').format(_endDate)}',
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: _selectDateRange,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Map layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(20.5937, 78.9629), // India center
              initialZoom: 5,
              backgroundColor: const Color(0xFF1a1a2e),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                maxZoom: 19,
                userAgentPackageName: 'com.wealthfam.mobile',
              ),
              if (_weightedPoints.isNotEmpty)
                HeatMapLayer(
                  heatMapDataSource: InMemoryHeatMapDataSource(data: _weightedPoints),
                  heatMapOptions: HeatMapOptions(
                    gradient: _heatGradient,
                    minOpacity: 0.3,
                    layerOpacity: 0.8,
                    radius: 30,
                    blurFactor: 15,
                  ),
                  reset: _rebuildStream.stream,
                ),
              if (_heatmapData.isNotEmpty)
                MarkerLayer(
                  markers: _heatmapData.map((p) {
                    final lat = (p['latitude'] as num).toDouble();
                    final lng = (p['longitude'] as num).toDouble();
                    final amount = (p['amount'] as num).toDouble();
                    final category = p['category'] ?? 'Expense';
                    final desc = p['description'] ?? '';

                    return Marker(
                      point: LatLng(lat, lng),
                      width: 24,
                      height: 24,
                      child: GestureDetector(
                        onTap: () => _showTransactionDetail(context, category, amount, desc, currency),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.9),
                            border: Border.all(color: AppTheme.primary, width: 2),
                            boxShadow: [
                              BoxShadow(color: AppTheme.primary.withOpacity(0.4), blurRadius: 6),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.circle, size: 8, color: AppTheme.primary),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    SizedBox(height: 16),
                    Text('Loading spending data...', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),

          // Error overlay
          if (_error != null && !_isLoading)
            Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: AppTheme.danger),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _fetchHeatmapData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),

          // Empty state overlay
          if (!_isLoading && _error == null && _heatmapData.isEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('📍', style: TextStyle(fontSize: 56)),
                    SizedBox(height: 16),
                    Text(
                      'No Geolocation Data',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Transactions with location coordinates\nwill appear on this map.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

          // Legend bar (bottom)
          if (_heatmapData.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    const Text('LOW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF3b82f6),
                              Color(0xFF10b981),
                              Color(0xFFf59e0b),
                              Color(0xFFef4444),
                              Color(0xFF7f1d1d),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('HIGH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_heatmapData.length} pts',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showTransactionDetail(BuildContext context, String category, double amount, String description, String currency) {
    final maskingFactor = context.read<DashboardService>().maskingFactor;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.location_on, color: AppTheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      Text(
                        '$currency${(amount / maskingFactor).toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
