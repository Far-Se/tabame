import 'dart:convert';
import 'package:flutter/material.dart';

enum BillingCycle {
  monthly,
  yearly,
  weekly,
}

class SubscriptionCategory {
  final String id;
  final String name;
  final int iconCodePoint;
  final String fontFamily; // To support flutter icons
  final Color color;

  SubscriptionCategory({
    required this.id,
    required this.name,
    required this.iconCodePoint,
    required this.color,
    this.fontFamily = 'MaterialIcons',
  });
  static List<SubscriptionCategory> get seedCategories => <SubscriptionCategory>[
        SubscriptionCategory(
          id: 'cat_entertainment',
          name: 'Entertainment',
          iconCodePoint: Icons.movie.codePoint,
          color: Colors.purpleAccent,
        ),
        SubscriptionCategory(
          id: 'cat_productivity',
          name: 'Productivity',
          iconCodePoint: Icons.work.codePoint,
          color: Colors.blueAccent,
        ),
        SubscriptionCategory(
          id: 'cat_health',
          name: 'Health',
          iconCodePoint: Icons.health_and_safety.codePoint,
          color: Colors.greenAccent,
        ),
        SubscriptionCategory(
          id: 'cat_finance',
          name: 'Finance',
          iconCodePoint: Icons.attach_money.codePoint,
          color: Colors.amberAccent,
        ),
        SubscriptionCategory(
          id: 'cat_shopping',
          name: 'Shopping',
          iconCodePoint: Icons.shopping_bag.codePoint,
          color: Colors.orangeAccent,
        ),
        SubscriptionCategory(
          id: 'cat_other',
          name: 'Other',
          iconCodePoint: Icons.category.codePoint,
          color: Colors.grey,
        ),
      ];
  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'iconCodePoint': iconCodePoint,
        'fontFamily': fontFamily,
        'color': color.toARGB32(),
      };

  factory SubscriptionCategory.fromMap(Map<String, dynamic> map) {
    return SubscriptionCategory(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      iconCodePoint: (map['iconCodePoint'] ?? 0) as int,
      fontFamily: (map['fontFamily'] ?? 'MaterialIcons').toString(),
      color: Color((map['color'] ?? 0xFFFFFFFF) as int),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory SubscriptionCategory.fromJson(String source) {
    return SubscriptionCategory.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}

class Subscription {
  final String id;
  final String name;
  final String logoUrl;
  final double amount;
  final String currency;
  final BillingCycle billingCycle;
  final DateTime startDate;
  final String categoryId;
  final Color color;
  final String? notes;
  final bool isActive;

  Subscription({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.amount,
    required this.currency,
    required this.billingCycle,
    required this.startDate,
    required this.categoryId,
    required this.color,
    this.notes,
    required this.isActive,
  });

  DateTime get nextBillingDate {
    final DateTime now = DateTime.now();
    DateTime nextDate = startDate;

    while (nextDate.isBefore(now) ||
        (nextDate.year == now.year && nextDate.month == now.month && nextDate.day == now.day)) {
      switch (billingCycle) {
        case BillingCycle.monthly:
          nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day);
          break;
        case BillingCycle.yearly:
          nextDate = DateTime(nextDate.year + 1, nextDate.month, nextDate.day);
          break;
        case BillingCycle.weekly:
          nextDate = nextDate.add(const Duration(days: 7));
          break;
      }
    }
    return nextDate;
  }

  bool isBillingOnDate(DateTime cellDate) {
    if (!isActive) return false;

    // Normalize both dates to midnight (Year, Month, Day only) to avoid time mismatches
    final DateTime normalizedCell = DateTime(cellDate.year, cellDate.month, cellDate.day);
    final DateTime normalizedStart = DateTime(startDate.year, startDate.month, startDate.day);

    // If the calendar cell is strictly before the day the subscription starts, skip it
    if (normalizedCell.isBefore(normalizedStart)) return false;

    // Check if it matches exactly on the start date day
    if (normalizedCell.isAtSameMomentAs(normalizedStart)) {
      return true;
    }

    switch (billingCycle) {
      case BillingCycle.weekly:
        // Calculate difference using midnights to get clean day multiples
        final int differenceInDays = normalizedCell.difference(normalizedStart).inDays;
        return differenceInDays % 7 == 0;

      case BillingCycle.monthly:
        // Must be the same calendar day of the month (e.g., every 18th)
        return normalizedCell.day == normalizedStart.day;

      case BillingCycle.yearly:
        // Must be the same month and the same day every year
        return normalizedCell.month == normalizedStart.month && normalizedCell.day == normalizedStart.day;
    }
  }

  double get totalSpentToDate {
    final DateTime now = DateTime.now();

    // If the subscription hasn't started yet or has an invalid amount, spent is 0
    if (now.isBefore(startDate) || amount <= 0) return 0.0;

    int occurrences = 1; // Includes the initial payment on startDate
    DateTime evaluationDate = startDate;

    while (true) {
      switch (billingCycle) {
        case BillingCycle.weekly:
          evaluationDate = evaluationDate.add(const Duration(days: 7));
          break;
        case BillingCycle.monthly:
          evaluationDate = DateTime(evaluationDate.year, evaluationDate.month + 1, evaluationDate.day);
          break;
        case BillingCycle.yearly:
          evaluationDate = DateTime(evaluationDate.year + 1, evaluationDate.month, evaluationDate.day);
          break;
      }

      // If the next billing occurrence day is in the future, stop counting
      if (evaluationDate.isAfter(now)) {
        break;
      }
      occurrences++;
    }

    return amount * occurrences;
  }

  double get normalizedMonthlyAmount {
    switch (billingCycle) {
      case BillingCycle.monthly:
        return amount;
      case BillingCycle.yearly:
        return amount / 12;
      case BillingCycle.weekly:
        return amount * 52 / 12;
    }
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'logoUrl': logoUrl,
        'amount': amount,
        'currency': currency,
        'billingCycle': billingCycle.index,
        'startDate': startDate.toIso8601String(),
        'categoryId': categoryId,
        'color': color.toARGB32(),
        'notes': notes,
        'isActive': isActive,
      };

  factory Subscription.fromMap(Map<String, dynamic> map) {
    return Subscription(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      logoUrl: (map['logoUrl'] ?? '').toString(),
      amount: (map['amount'] ?? 0.0) as double,
      currency: (map['currency'] ?? '').toString(),
      billingCycle: BillingCycle.values[(map['billingCycle'] ?? 0) as int],
      startDate: DateTime.parse((map['startDate'] ?? DateTime.now().toIso8601String()).toString()),
      categoryId: (map['categoryId'] ?? '').toString(),
      color: Color((map['color'] ?? 0xFFFFFFFF) as int),
      notes: map['notes']?.toString(),
      isActive: (map['isActive'] ?? true) as bool,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Subscription.fromJson(String source) {
    return Subscription.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
