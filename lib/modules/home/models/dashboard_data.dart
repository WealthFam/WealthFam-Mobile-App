import 'package:intl/intl.dart';
import 'package:decimal/decimal.dart';

Decimal _toDecimal(dynamic value) {
  if (value == null) return Decimal.zero;
  if (value is num) return Decimal.parse(value.toString());
  if (value is String) return Decimal.tryParse(value) ?? Decimal.zero;
  return Decimal.zero;
}

class DashboardData {
  final DashboardSummary summary;
  final BudgetSummary budget;
  final InvestmentSummary? investmentSummary;
  final List<SpendingTrendItem> spendingTrend;
  final List<CategoryPieItem> categoryDistribution;
  final List<MonthTrendItem> monthWiseTrend;
  final List<RecentTransaction> recentTransactions;
  final int pendingTriageCount;
  final int pendingTrainingCount;
  final int? familyMembersCount;

  DashboardData({
    required this.summary,
    required this.budget,
    this.investmentSummary,
    required this.spendingTrend,
    required this.categoryDistribution,
    required this.monthWiseTrend,
    required this.recentTransactions,
    this.pendingTriageCount = 0,
    this.pendingTrainingCount = 0,
    this.familyMembersCount,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    return DashboardData(
      summary: DashboardSummary.fromJson(json['summary']),
      budget: BudgetSummary.fromJson(json['budget']),
      investmentSummary: json['investment_summary'] != null ? InvestmentSummary.fromJson(json['investment_summary']) : null,
      spendingTrend: (json['spending_trend'] as List? ?? [])
          .map((i) => SpendingTrendItem.fromJson(i))
          .toList(),
      categoryDistribution: (json['category_distribution'] as List? ?? [])
          .map((i) => CategoryPieItem.fromJson(i))
          .toList(),
      monthWiseTrend: (json['month_wise_trend'] as List? ?? [])
          .map((i) => MonthTrendItem.fromJson(i))
          .toList(),
      recentTransactions: (json['recent_transactions'] as List? ?? [])
          .map((i) => RecentTransaction.fromJson(i))
          .toList(),
      pendingTriageCount: json['pending_triage_count'] ?? 0,
      pendingTrainingCount: json['pending_training_count'] ?? 0,
      familyMembersCount: json['family_members_count'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary': summary.toJson(),
      'budget': budget.toJson(),
      'investment_summary': investmentSummary?.toJson(),
      'spending_trend': spendingTrend.map((i) => i.toJson()).toList(),
      'category_distribution': categoryDistribution.map((i) => i.toJson()).toList(),
      'month_wise_trend': monthWiseTrend.map((i) => i.toJson()).toList(),
      'recent_transactions': recentTransactions.map((i) => i.toJson()).toList(),
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
      pendingTriageCount: pendingTriageCount ?? this.pendingTriageCount,
      pendingTrainingCount: pendingTrainingCount ?? this.pendingTrainingCount,
      familyMembersCount: familyMembersCount ?? this.familyMembersCount,
    );
  }
}

class SpendingTrendItem {
  final String date;
  final Decimal amount;
  final Decimal dailyLimit;

  SpendingTrendItem({required this.date, required this.amount, required this.dailyLimit});

  factory SpendingTrendItem.fromJson(Map<String, dynamic> json) {
    return SpendingTrendItem(
      date: json['date'],
      amount: _toDecimal(json['amount']),
      dailyLimit: _toDecimal(json['daily_limit']),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'amount': amount.toString(),
    'daily_limit': dailyLimit.toString(),
  };
  
  DateTime get dateTime => DateTime.parse(date).toLocal();
}

class CategoryPieItem {
  final String name;
  final Decimal value;

  CategoryPieItem({required this.name, required this.value});

  factory CategoryPieItem.fromJson(Map<String, dynamic> json) {
    return CategoryPieItem(
      name: json['name'],
      value: _toDecimal(json['value']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value.toString(),
  };
}

class DashboardSummary {
  final Decimal todayTotal;
  final Decimal yesterdayTotal;
  final Decimal lastMonthSameDayTotal;
  final Decimal monthlyTotal;
  final String currency;
  final Decimal dailyBudgetLimit;
  final Decimal proratedBudget;

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
      currency: json['currency'] ?? 'INR',
      dailyBudgetLimit: _toDecimal(json['daily_budget_limit']),
      proratedBudget: _toDecimal(json['prorated_budget']),
    );
  }

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
  final Decimal limit;
  final Decimal spent;
  final Decimal percentage;

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

  Map<String, dynamic> toJson() => {
    'limit': limit.toString(),
    'spent': spent.toString(),
    'percentage': percentage.toString(),
  };
}

class InvestmentSummary {
  final Decimal totalInvested;
  final Decimal currentValue;
  final Decimal profitLoss;
  final Decimal? xirr;
  final List<double> sparkline;
  final Decimal dayChange;
  final Decimal dayChangePercent;

  InvestmentSummary({
    required this.totalInvested,
    required this.currentValue,
    required this.profitLoss,
    this.xirr,
    this.sparkline = const [],
    required this.dayChange,
    required this.dayChangePercent,
  });

  factory InvestmentSummary.fromJson(Map<String, dynamic> json) {
    return InvestmentSummary(
      totalInvested: _toDecimal(json['total_invested']),
      currentValue: _toDecimal(json['current_value']),
      profitLoss: _toDecimal(json['profit_loss']),
      xirr: json['xirr'] != null ? _toDecimal(json['xirr']) : null,
      sparkline: (json['sparkline'] as List? ?? []).map((v) => (v as num).toDouble()).toList(),
      dayChange: _toDecimal(json['day_change']),
      dayChangePercent: _toDecimal(json['day_change_percent']),
    );
  }

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
  final String id;
  final DateTime date;
  final String description;
  final Decimal amount;
  final String category;
  final String? accountName;
  final String? accountOwnerName;
  final bool isHidden;
  final String? expenseGroupId;
  final String? expenseGroupName;
  final String? source;

  RecentTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    required this.category,
    this.accountName,
    this.accountOwnerName,
    this.isHidden = false,
    this.expenseGroupId,
    this.expenseGroupName,
    this.source,
  });

  factory RecentTransaction.fromJson(Map<String, dynamic> json) {
    return RecentTransaction(
      id: json['id'],
      date: DateTime.parse(json['date']).toLocal(),
      description: json['description'] ?? '',
      amount: _toDecimal(json['amount']),
      category: json['category'] ?? 'Uncategorized',
      accountName: json['account_name'],
      accountOwnerName: json['account_owner_name'],
      isHidden: json['is_hidden'] ?? false,
      expenseGroupId: json['expense_group_id'],
      expenseGroupName: json['expense_group_name'],
      source: json['source'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toUtc().toIso8601String(),
    'description': description,
    'amount': amount.toString(),
    'category': category,
    'account_name': accountName,
    'account_owner_name': accountOwnerName,
    'is_hidden': isHidden,
    'expense_group_id': expenseGroupId,
    'expense_group_name': expenseGroupName,
    'source': source,
  };

  String get formattedDate => DateFormat('MMM d, h:mm a').format(date);
}

class MonthTrendItem {
  final String month;
  final Decimal spent;
  final Decimal budget;
  final bool isSelected;

  MonthTrendItem({
    required this.month, 
    required this.spent, 
    required this.budget,
    this.isSelected = false,
  });

  factory MonthTrendItem.fromJson(Map<String, dynamic> json) {
    return MonthTrendItem(
      month: json['month'],
      spent: _toDecimal(json['spent']),
      budget: _toDecimal(json['budget']),
      isSelected: json['is_selected'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'month': month,
    'spent': spent.toString(),
    'budget': budget.toString(),
    'is_selected': isSelected,
  };
}
