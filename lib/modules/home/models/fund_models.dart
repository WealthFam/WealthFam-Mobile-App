import 'package:decimal/decimal.dart';

Decimal _toDecimal(dynamic value) {
  if (value == null) return Decimal.zero;
  if (value is num) return Decimal.parse(value.toString());
  if (value is String) return Decimal.tryParse(value) ?? Decimal.zero;
  return Decimal.zero;
}

double _toDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
}

class FundHolding {

  FundHolding({
    required this.schemeCode,
    required this.schemeName,
    required this.units,
    required this.currentValue,
    required this.investedValue,
    required this.profitLoss,
    required this.lastUpdated,
    required this.dayChange,
    required this.dayChangePercentage,
  });

  factory FundHolding.fromJson(Map<String, dynamic> json) {
    return FundHolding(
      schemeCode: json['scheme_code'] as String,
      schemeName: json['scheme_name'] as String,
      units: _toDouble(json['units']),
      currentValue: _toDecimal(json['current_value']),
      investedValue: _toDecimal(json['invested_value']),
      profitLoss: _toDecimal(json['profit_loss']),
      lastUpdated: json['last_updated'] as String? ?? '',
      dayChange: _toDecimal(json['day_change']),
      dayChangePercentage: _toDecimal(json['day_change_percentage']),
    );
  }
  final String schemeCode;
  final String schemeName;
  final double units;
  final Decimal currentValue;
  final Decimal investedValue;
  final Decimal profitLoss;
  final Decimal dayChange;
  final Decimal dayChangePercentage;
  final String lastUpdated;

  Map<String, dynamic> toJson() {
    return {
      'scheme_code': schemeCode,
      'scheme_name': schemeName,
      'units': units,
      'current_value': currentValue.toString(),
      'invested_value': investedValue.toString(),
      'profit_loss': profitLoss.toString(),
      'last_updated': lastUpdated,
      'day_change': dayChange.toString(),
      'day_change_percentage': dayChangePercentage.toString(),
    };
  }
}

class PortfolioSummary {

  PortfolioSummary({
    required this.totalInvested,
    required this.totalCurrent,
    required this.totalPl,
    required this.dayChange,
    required this.dayChangePercentage,
    required this.holdings,
  });

  factory PortfolioSummary.fromJson(Map<String, dynamic> json) {
    return PortfolioSummary(
      totalInvested: _toDecimal(json['total_invested']),
      totalCurrent: _toDecimal(json['total_current']),
      totalPl: _toDecimal(json['total_pl']),
      dayChange: _toDecimal(json['day_change']),
      dayChangePercentage: _toDecimal(json['day_change_percentage']),
      holdings:
          (json['holdings'] as List)
              .map((i) => FundHolding.fromJson(i as Map<String, dynamic>))
              .toList(),
    );
  }
  final Decimal totalInvested;
  final Decimal totalCurrent;
  final Decimal totalPl;
  final Decimal dayChange;
  final Decimal dayChangePercentage;
  final List<FundHolding> holdings;

  Map<String, dynamic> toJson() {
    return {
      'total_invested': totalInvested.toString(),
      'total_current': totalCurrent.toString(),
      'total_pl': totalPl.toString(),
      'day_change': dayChange.toString(),
      'day_change_percentage': dayChangePercentage.toString(),
      'holdings': holdings.map((h) => h.toJson()).toList(),
    };
  }
}
