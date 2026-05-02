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

class Folio {
  Folio({
    required this.folioNumber,
    required this.units,
    required this.currentValue,
    required this.investedValue,
    required this.profitLoss,
  });

  factory Folio.fromJson(Map<String, dynamic> json) {
    return Folio(
      folioNumber: json['folio_number'] as String,
      units: _toDouble(json['units']),
      currentValue: _toDecimal(json['current_value']),
      investedValue: _toDecimal(json['invested_value']),
      profitLoss: _toDecimal(json['profit_loss']),
    );
  }

  final String folioNumber;
  final double units;
  final Decimal currentValue;
  final Decimal investedValue;
  final Decimal profitLoss;
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
    this.category,
    this.xirr,
    this.folios = const [],
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
      category: json['category'] as String?,
      xirr: json['xirr'] != null ? _toDouble(json['xirr']) : null,
      folios: (json['folios'] as List?)
              ?.map((i) => Folio.fromJson(i as Map<String, dynamic>))
              .toList() ??
          const [],
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
  final String? category;
  final double? xirr;
  final List<Folio> folios;

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
      'category': category,
      'xirr': xirr,
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
    this.xirr,
    this.assetAllocation,
    this.topGainers = const [],
    this.topLosers = const [],
    this.textInsights = const [],
  });

  factory PortfolioSummary.fromJson(Map<String, dynamic> json) {
    return PortfolioSummary(
      totalInvested: _toDecimal(json['total_invested']),
      totalCurrent: _toDecimal(json['total_current']),
      totalPl: _toDecimal(json['total_pl']),
      dayChange: _toDecimal(json['day_change']),
      dayChangePercentage: _toDecimal(json['day_change_percentage']),
      xirr: json['xirr'] != null ? _toDouble(json['xirr']) : null,
      assetAllocation: (json['asset_allocation'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, _toDouble(v))),
      topGainers: (json['top_gainers'] as List?)
              ?.map((i) => FundHolding.fromJson(i as Map<String, dynamic>))
              .toList() ??
          const [],
      topLosers: (json['top_losers'] as List?)
              ?.map((i) => FundHolding.fromJson(i as Map<String, dynamic>))
              .toList() ??
          const [],
      textInsights: (json['text_insights'] as List?)?.cast<String>() ?? const [],
      holdings: (json['holdings'] as List)
          .map((i) => FundHolding.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
  final Decimal totalInvested;
  final Decimal totalCurrent;
  final Decimal totalPl;
  final Decimal dayChange;
  final Decimal dayChangePercentage;
  final double? xirr;
  final Map<String, double>? assetAllocation;
  final List<FundHolding> topGainers;
  final List<FundHolding> topLosers;
  final List<String> textInsights;
  final List<FundHolding> holdings;

  Map<String, dynamic> toJson() {
    return {
      'total_invested': totalInvested.toString(),
      'total_current': totalCurrent.toString(),
      'total_pl': totalPl.toString(),
      'day_change': dayChange.toString(),
      'day_change_percentage': dayChangePercentage.toString(),
      'xirr': xirr,
      'holdings': holdings.map((h) => h.toJson()).toList(),
    };
  }
}

class TimelinePoint {
  TimelinePoint({
    required this.date,
    required this.value,
    this.benchmarkValue,
  });

  factory TimelinePoint.fromJson(Map<String, dynamic> json) {
    return TimelinePoint(
      date: json['date'] as String,
      value: _toDouble(json['value']),
      benchmarkValue: json['benchmark_value'] != null
          ? _toDouble(json['benchmark_value'])
          : null,
    );
  }

  final String date;
  final double value;
  final double? benchmarkValue;
}

class InvestmentEvent {
  InvestmentEvent({
    required this.date,
    required this.amount,
    required this.type,
    required this.units,
  });

  factory InvestmentEvent.fromJson(Map<String, dynamic> json) {
    return InvestmentEvent(
      date: json['date'] as String,
      amount: _toDouble(json['amount']),
      type: json['type'] as String,
      units: _toDouble(json['units']),
    );
  }

  final String date;
  final double amount;
  final String type;
  final double units;
}

class FundDetailResponse {
  FundDetailResponse({
    required this.schemeCode,
    required this.schemeName,
    required this.category,
    required this.totalUnits,
    required this.currentValue,
    required this.investedValue,
    required this.profitLoss,
    required this.profitLossPercentage,
    required this.dayChange,
    required this.dayChangePercentage,
    required this.folios,
    required this.timeline,
    required this.events,
    this.fundHouse,
    this.xirr,
  });

  factory FundDetailResponse.fromJson(Map<String, dynamic> json) {
    return FundDetailResponse(
      schemeCode: json['scheme_code'] as String,
      schemeName: json['scheme_name'] as String,
      category: json['category'] as String,
      fundHouse: json['fund_house'] as String?,
      totalUnits: _toDouble(json['total_units']),
      currentValue: _toDecimal(json['current_value']),
      investedValue: _toDecimal(json['invested_value']),
      profitLoss: _toDecimal(json['profit_loss']),
      profitLossPercentage: _toDouble(json['profit_loss_percentage']),
      dayChange: _toDecimal(json['day_change']),
      dayChangePercentage: _toDouble(json['day_change_percentage']),
      xirr: json['xirr'] != null ? _toDouble(json['xirr']) : null,
      folios: (json['folios'] as List)
          .map((i) => Folio.fromJson(i as Map<String, dynamic>))
          .toList(),
      timeline: (json['timeline'] as List)
          .map((i) => TimelinePoint.fromJson(i as Map<String, dynamic>))
          .toList(),
      events: (json['events'] as List)
          .map((i) => InvestmentEvent.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }

  final String schemeCode;
  final String schemeName;
  final String category;
  final String? fundHouse;
  final double totalUnits;
  final Decimal currentValue;
  final Decimal investedValue;
  final Decimal profitLoss;
  final double profitLossPercentage;
  final Decimal dayChange;
  final double dayChangePercentage;
  final double? xirr;
  final List<Folio> folios;
  final List<TimelinePoint> timeline;
  final List<InvestmentEvent> events;
}
