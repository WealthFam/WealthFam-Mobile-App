import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

Decimal _toDecimal(dynamic value) {
  if (value == null) return Decimal.zero;
  if (value is num) return Decimal.parse(value.toString());
  if (value is String) return Decimal.tryParse(value) ?? Decimal.zero;
  return Decimal.zero;
}

class DashboardData {

  DashboardData({
    required this.summary,
    required this.budget,
    required this.spendingTrend, required this.categoryDistribution, required this.monthWiseTrend, required this.recentTransactions, this.investmentSummary,
    this.calendarHeatmap = const {},
    this.pendingTriageCount = 0,
    this.pendingTrainingCount = 0,
    this.familyMembersCount,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      summary: DashboardSummary.fromJson(json['summary'] as Map<String, dynamic>),
      budget: BudgetSummary.fromJson(json['budget'] as Map<String, dynamic>),
      investmentSummary: json['investment_summary'] != null
          ? InvestmentSummary.fromJson(
            json['investment_summary'] as Map<String, dynamic>,
          )
          : null,
      spendingTrend:
          (json['spending_trend'] as List? ?? [])
              .map((i) => SpendingTrendItem.fromJson(i as Map<String, dynamic>))
              .toList(),
      categoryDistribution:
          (json['category_distribution'] as List? ?? [])
              .map((i) => CategoryPieItem.fromJson(i as Map<String, dynamic>))
              .toList(),
      monthWiseTrend:
          (json['month_wise_trend'] as List? ?? [])
              .map((i) => MonthTrendItem.fromJson(i as Map<String, dynamic>))
              .toList(),
      recentTransactions:
          (json['recent_transactions'] as List? ?? [])
              .map((i) => RecentTransaction.fromJson(i as Map<String, dynamic>))
              .toList(),
      calendarHeatmap:
          (json['calendar_heatmap'] as Map<String, dynamic>? ?? {}).map(
            (k, v) => MapEntry(k, _toDecimal(v)),
          ),
      pendingTriageCount: json['pending_triage_count'] as int? ?? 0,
      pendingTrainingCount: json['pending_training_count'] as int? ?? 0,
      familyMembersCount: json['family_members_count'] as int?,
    );
  }
  final DashboardSummary summary;
  final BudgetSummary budget;
  final InvestmentSummary? investmentSummary;
  final List<SpendingTrendItem> spendingTrend;
  final List<CategoryPieItem> categoryDistribution;
  final List<MonthTrendItem> monthWiseTrend;
  final List<RecentTransaction> recentTransactions;
  final Map<String, Decimal> calendarHeatmap;
  final int pendingTriageCount;
  final int pendingTrainingCount;
  final int? familyMembersCount;

  Map<String, dynamic> toJson() {
    return {
      'summary': summary.toJson(),
      'budget': budget.toJson(),
      'investment_summary': investmentSummary?.toJson(),
      'spending_trend': spendingTrend.map((i) => i.toJson()).toList(),
      'category_distribution': categoryDistribution
          .map((i) => i.toJson())
          .toList(),
      'month_wise_trend': monthWiseTrend.map((i) => i.toJson()).toList(),
      'recent_transactions': recentTransactions.map((i) => i.toJson()).toList(),
      'calendar_heatmap': calendarHeatmap.map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      'pending_triage_count': pendingTriageCount,
      'pending_training_count': pendingTrainingCount,
      'family_members_count': familyMembersCount,
    };
  }

  DashboardData copyWith({
    DashboardSummary? summary,
    BudgetSummary? budget,
    InvestmentSummary? investmentSummary,
    List<SpendingTrendItem>? spendingTrend,
    List<CategoryPieItem>? categoryDistribution,
    List<MonthTrendItem>? monthWiseTrend,
    List<RecentTransaction>? recentTransactions,
    Map<String, Decimal>? calendarHeatmap,
    int? pendingTriageCount,
    int? pendingTrainingCount,
    int? familyMembersCount,
  }) {
    return DashboardData(
      summary: summary ?? this.summary,
      budget: budget ?? this.budget,
      investmentSummary: investmentSummary ?? this.investmentSummary,
      spendingTrend: spendingTrend ?? this.spendingTrend,
      categoryDistribution: categoryDistribution ?? this.categoryDistribution,
      monthWiseTrend: monthWiseTrend ?? this.monthWiseTrend,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      calendarHeatmap: calendarHeatmap ?? this.calendarHeatmap,
      pendingTriageCount: pendingTriageCount ?? this.pendingTriageCount,
      pendingTrainingCount: pendingTrainingCount ?? this.pendingTrainingCount,
      familyMembersCount: familyMembersCount ?? this.familyMembersCount,
    );
  }
}

class SpendingTrendItem {

  SpendingTrendItem({
    required this.date,
    required this.amount,
    required this.dailyLimit,
  });

  factory SpendingTrendItem.fromJson(Map<String, dynamic> json) {
    return SpendingTrendItem(
      date: json['date'] as String,
      amount: _toDecimal(json['amount']),
      dailyLimit: _toDecimal(json['daily_limit']),
    );
  }
  final String date;
  final Decimal amount;
  final Decimal dailyLimit;

  Map<String, dynamic> toJson() => {
    'date': date,
    'amount': amount.toString(),
    'daily_limit': dailyLimit.toString(),
  };

  DateTime get dateTime => DateTime.parse(date).toLocal();
}

class CategoryPieItem {

  CategoryPieItem({required this.name, required this.value});

  factory CategoryPieItem.fromJson(Map<String, dynamic> json) {
    return CategoryPieItem(
      name: json['name'] as String,
      value: _toDecimal(json['value']),
    );
  }
  final String name;
  final Decimal value;

  Map<String, dynamic> toJson() => {'name': name, 'value': value.toString()};
}

class DashboardSummary {

  DashboardSummary({
    required this.todayTotal,
    required this.yesterdayTotal,
    required this.lastMonthSameDayTotal,
    required this.monthlyTotal,
    required this.currency,
    required this.dailyBudgetLimit,
    required this.proratedBudget,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      todayTotal: _toDecimal(json['today_total']),
      yesterdayTotal: _toDecimal(json['yesterday_total']),
      lastMonthSameDayTotal: _toDecimal(json['last_month_same_day_total']),
      monthlyTotal: _toDecimal(json['monthly_total']),
      currency: json['currency'] as String? ?? 'INR',
      dailyBudgetLimit: _toDecimal(json['daily_budget_limit']),
      proratedBudget: _toDecimal(json['prorated_budget']),
    );
  }
  final Decimal todayTotal;
  final Decimal yesterdayTotal;
  final Decimal lastMonthSameDayTotal;
  final Decimal monthlyTotal;
  final String currency;
  final Decimal dailyBudgetLimit;
  final Decimal proratedBudget;

  Map<String, dynamic> toJson() => {
    'today_total': todayTotal.toString(),
    'yesterday_total': yesterdayTotal.toString(),
    'last_month_same_day_total': lastMonthSameDayTotal.toString(),
    'monthly_total': monthlyTotal.toString(),
    'currency': currency,
    'daily_budget_limit': dailyBudgetLimit.toString(),
    'prorated_budget': proratedBudget.toString(),
  };
}

class BudgetSummary {

  BudgetSummary({
    required this.limit,
    required this.spent,
    required this.percentage,
  });

  factory BudgetSummary.fromJson(Map<String, dynamic> json) {
    return BudgetSummary(
      limit: _toDecimal(json['limit']),
      spent: _toDecimal(json['spent']),
      percentage: _toDecimal(json['percentage']),
    );
  }
  final Decimal limit;
  final Decimal spent;
  final Decimal percentage;

  Map<String, dynamic> toJson() => {
    'limit': limit.toString(),
    'spent': spent.toString(),
    'percentage': percentage.toString(),
  };
}

class InvestmentSummary {

  InvestmentSummary({
    required this.totalInvested,
    required this.currentValue,
    required this.profitLoss,
    required this.dayChange, required this.dayChangePercent, this.xirr,
    this.sparkline = const [],
  });

  factory InvestmentSummary.fromJson(Map<String, dynamic> json) {
    return InvestmentSummary(
      totalInvested: _toDecimal(json['total_invested']),
      currentValue: _toDecimal(json['current_value']),
      profitLoss: _toDecimal(json['profit_loss']),
      xirr: json['xirr'] != null ? _toDecimal(json['xirr']) : null,
      sparkline: (json['sparkline'] as List? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      dayChange: _toDecimal(json['day_change']),
      dayChangePercent: _toDecimal(json['day_change_percent']),
    );
  }
  final Decimal totalInvested;
  final Decimal currentValue;
  final Decimal profitLoss;
  final Decimal? xirr;
  final List<double> sparkline;
  final Decimal dayChange;
  final Decimal dayChangePercent;

  Map<String, dynamic> toJson() => {
    'total_invested': totalInvested.toString(),
    'current_value': currentValue.toString(),
    'profit_loss': profitLoss.toString(),
    'xirr': xirr?.toString(),
    'sparkline': sparkline,
    'day_change': dayChange.toString(),
    'day_change_percent': dayChangePercent.toString(),
  };
}

class RecentTransaction {

  RecentTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.category,
    this.accountId,
    this.accountName,
    this.accountOwnerName,
    this.isHidden = false,
    this.isTransfer = false,
    this.excludeFromReports = false,
    this.expenseGroupId,
    this.expenseGroupName,
    this.source,
    this.hasDocuments = false,
  });

  factory RecentTransaction.fromJson(Map<String, dynamic> json) {
    return RecentTransaction(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String).toLocal(),
      description: json['description'] as String? ?? '',
      amount: _toDecimal(json['amount']),
      category: json['category'] as String? ?? 'Uncategorized',
      accountId: json['account_id'] as String?,
      accountName: json['account_name'] as String?,
      accountOwnerName: json['account_owner_name'] as String?,
      isHidden: json['is_hidden'] as bool? ?? false,
      isTransfer: json['is_transfer'] as bool? ?? false,
      excludeFromReports: json['exclude_from_reports'] as bool? ?? false,
      expenseGroupId: json['expense_group_id'] as String?,
      expenseGroupName: json['expense_group_name'] as String?,
      source: json['source'] as String?,
      hasDocuments: json['has_documents'] as bool? ?? false,
    );
  }
  final String id;
  final DateTime date;
  final String description;
  final Decimal amount;
  final String category;
  final String? accountId;
  final String? accountName;
  final String? accountOwnerName;
  final bool isHidden;
  final bool isTransfer;
  final bool excludeFromReports;
  final String? expenseGroupId;
  final String? expenseGroupName;
  final String? source;
  final bool hasDocuments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toUtc().toIso8601String(),
    'description': description,
    'amount': amount.toString(),
    'category': category,
    'account_id': accountId,
    'account_name': accountName,
    'account_owner_name': accountOwnerName,
    'is_hidden': isHidden,
    'is_transfer': isTransfer,
    'exclude_from_reports': excludeFromReports,
    'expense_group_id': expenseGroupId,
    'expense_group_name': expenseGroupName,
    'source': source,
    'has_documents': hasDocuments,
  };

  String get formattedDate => DateFormat('MMM d, h:mm a').format(date);
}

class MonthTrendItem {

  MonthTrendItem({
    required this.month,
    required this.spent,
    required this.budget,
    this.isSelected = false,
  });

  factory MonthTrendItem.fromJson(Map<String, dynamic> json) {
    return MonthTrendItem(
      month: json['month'] as String,
      spent: _toDecimal(json['spent']),
      budget: _toDecimal(json['budget']),
      isSelected: json['is_selected'] as bool? ?? false,
    );
  }
  final String month;
  final Decimal spent;
  final Decimal budget;
  final bool isSelected;

  Map<String, dynamic> toJson() => {
    'month': month,
    'spent': spent.toString(),
    'budget': budget.toString(),
    'is_selected': isSelected,
  };
}
