import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_app/core/config/app_config.dart';
import 'package:mobile_app/core/theme/app_theme.dart';
import 'package:mobile_app/modules/auth/services/auth_service.dart';
import 'package:mobile_app/modules/home/services/dashboard_service.dart';
import 'package:mobile_app/core/errors/either.dart';

class SpendingHeatmapWidget extends StatefulWidget {
  const SpendingHeatmapWidget({super.key});

  @override
  State<SpendingHeatmapWidget> createState() => _SpendingHeatmapWidgetState();
}

class _SpendingHeatmapWidgetState extends State<SpendingHeatmapWidget> {
  List<dynamic> _heatmapData = [];
  List<WeightedLatLng> _weightedPoints = [];
  bool _isLoading = true;
  String? _error;
  final MapController _mapController = MapController();
  final StreamController<void> _rebuildStream = StreamController.broadcast();
  DashboardService? _dashboard;

  static final Map<double, MaterialColor> _heatGradient = {
    0.25: Colors.blue,
    0.55: Colors.green,
    0.85: Colors.orange,
    1.00: Colors.red,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dashboard = context.read<DashboardService>();
      _dashboard?.addListener(_fetchHeatmapData);
      _fetchHeatmapData();
    });
  }

  @override
  void dispose() {
    _dashboard?.removeListener(_fetchHeatmapData);
    _rebuildStream.close();
    super.dispose();
  }

  Future<void> _fetchHeatmapData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final dashboard = _dashboard;
    if (dashboard == null) return;

    final result = await dashboard.fetchGeographicalHeatmap(
      month: dashboard.selectedMonth,
      year: dashboard.selectedYear,
      memberId: dashboard.selectedMemberId,
    );

    if (mounted) {
      result.fold(
        (failure) {
          setState(() {
            _error = failure.message;
            _isLoading = false;
          });
        },
        (data) {
          final weighted = data.map((p) {
            final lat = (p['latitude'] as num).toDouble();
            final lng = (p['longitude'] as num).toDouble();
            final amt = (p['amount'] as num).toDouble();
            return WeightedLatLng(LatLng(lat, lng), amt);
          }).toList();

          setState(() {
            _heatmapData = data;
            _weightedPoints = weighted;
            _isLoading = false;
          });

          if (weighted.isNotEmpty) {
            _rebuildStream.add(null);
            _fitMapBounds();
          }
        },
      );
    }
  }

  void _fitMapBounds() {
    if (_heatmapData.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      if (_heatmapData.length == 1) {
        final p = _heatmapData[0];
        _mapController.move(
          LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble()),
          12,
        );
      } else {
        final points = _heatmapData.map((p) =>
          LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble())
        ).toList();

        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = context.read<DashboardService>().currencySymbol;

    return Container(
      height: 350,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor.withOpacity(0.5)),
      ),
      child: Stack(
        children: [
          // Map layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(20.5937, 78.9629),
              initialZoom: 5,
              backgroundColor: const Color(0xFF1a1a2e),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                maxZoom: 19,
                retinaMode: RetinaMode.isHighDensity(context),
                userAgentPackageName: 'com.wealthfam.mobile',
              ),
              if (_weightedPoints.isNotEmpty)
                HeatMapLayer(
                  heatMapDataSource: InMemoryHeatMapDataSource(data: _weightedPoints),
                  heatMapOptions: HeatMapOptions(
                    gradient: _heatGradient,
                    minOpacity: 0.3,
                    layerOpacity: 0.8,
                    radius: 25,
                    blurFactor: 12,
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
                      width: 20,
                      height: 20,
                      child: GestureDetector(
                        onTap: () => _showTransactionDetail(context, category, amount, desc, currency),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.9),
                            border: Border.all(color: AppTheme.primary, width: 2),
                          ),
                          child: const Center(
                            child: Icon(Icons.circle, size: 6, color: AppTheme.primary),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),

          // Legend & Info bar
          if (_heatmapData.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Text('HEATMAP', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: const LinearGradient(
                            colors: [Colors.blue, Colors.green, Colors.orange, Colors.red],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_heatmapData.length} LOCATIONS',
                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),

          // Loading overlay
          if (_isLoading)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),

          // Error/Empty state overlay
          if (!_isLoading && (_error != null || _heatmapData.isEmpty))
            Container(
              color: Colors.black54,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error != null ? '⚠️' : '📍',
                        style: const TextStyle(fontSize: 32),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error ?? 'No location data for this period',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (_error != null)
                        TextButton(
                          onPressed: _fetchHeatmapData,
                          child: const Text('Retry', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
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
