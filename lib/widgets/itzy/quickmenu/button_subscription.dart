// ignore_for_file: non_const_argument_for_const_parameter

import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../models/classes/authenticator_entry.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/classes/subscription_models.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/modern_dropdown.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';
import 'button_authenticator.dart';

class SubscriptionPanelButton extends StatelessWidget {
  const SubscriptionPanelButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Subscriptions",
        icon: const Icon(Icons.subscriptions_outlined),
        child: () => const SubscriptionPanel());
  }
}

class SubscriptionPanel extends StatefulWidget {
  const SubscriptionPanel({super.key});

  @override
  State<SubscriptionPanel> createState() => _SubscriptionPanelState();
}

class SubsBox {
  List<Subscription> get subscriptions {
    final String savedJson = Boxes.pref.getString('subscriptions') ?? '';
    if (savedJson.isEmpty) return <Subscription>[];
    try {
      return (jsonDecode(savedJson) as List<dynamic>)
          .map((dynamic e) => Subscription.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Subscription>[];
    }
  }

  set subscriptions(List<Subscription> list) {
    Boxes.updateSettings(
      'subscriptions',
      jsonEncode(list.map((Subscription e) => e.toMap()).toList()),
    );
  }

  List<SubscriptionCategory> get subscriptionCategories {
    final String savedJson = Boxes.pref.getString('subscriptionCategories') ?? '';
    if (savedJson.isEmpty) return SubscriptionCategory.seedCategories;
    try {
      return (jsonDecode(savedJson) as List<dynamic>)
          .map((dynamic e) => SubscriptionCategory.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return SubscriptionCategory.seedCategories;
    }
  }

  set subscriptionCategories(List<SubscriptionCategory> list) {
    Boxes.updateSettings(
      'subscriptionCategories',
      jsonEncode(list.map((SubscriptionCategory e) => e.toMap()).toList()),
    );
  }
}

class _SubscriptionPanelState extends State<SubscriptionPanel> {
  int _currentIndex = 0;
  late List<Subscription> _subscriptions;
  late List<SubscriptionCategory> _categories;
  final SubsBox subBox = SubsBox();

  bool _isEditing = false;
  Subscription? _editingSubscription;

  @override
  void initState() {
    super.initState();
    _subscriptions = subBox.subscriptions;
    _categories = subBox.subscriptionCategories;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // width: 400,
      // height: 600,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: <Widget>[
          if (_isEditing)
            _buildEditorHeader()
          else
            PanelHeader(
              title: "Subscriptions",
              icon: Icons.subscriptions,
              accent: userSettings.themeColors.accentColor,
              buttonPressed: () => Navigator.of(context).pop(),
              buttonIcon: Icons.close,
            ),
          if (!_isEditing) _buildTabs(),
          Expanded(
            child: _isEditing
                ? SubscriptionForm(
                    categories: _categories,
                    subscription: _editingSubscription,
                    onSave: (Subscription sub) {
                      setState(() {
                        if (_editingSubscription == null) {
                          _subscriptions.add(sub);
                        } else {
                          final int idx = _subscriptions.indexWhere((Subscription e) => e.id == sub.id);
                          if (idx != -1) _subscriptions[idx] = sub;
                        }
                        subBox.subscriptions = _subscriptions;
                        _isEditing = false;
                        _editingSubscription = null;
                      });
                    },
                  )
                : (_currentIndex == 0
                    ? SubscriptionCalendarView(
                        subscriptions: _subscriptions,
                        categories: _categories,
                        onAddOrEdit: _showAddEditModal,
                      )
                    : SubscriptionInsightsView(
                        subscriptions: _subscriptions,
                        categories: _categories,
                        onEdit: _showAddEditModal,
                        onDelete: _deleteSubscription,
                      )),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorHeader() {
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: accent.withAlpha(40),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          InkWell(
            onTap: () {
              setState(() {
                _isEditing = false;
                _editingSubscription = null;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accent.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _editingSubscription == null ? "New Subscription" : "Edit Subscription",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: <Widget>[
          _buildTab("Calendar", 0, Icons.calendar_month),
          const SizedBox(width: 8),
          _buildTab("Insights", 1, Icons.pie_chart),
        ],
      ),
    );
  }

  Widget _buildTab(String title, int index, IconData icon) {
    final bool isSelected = _currentIndex == index;
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _currentIndex = index),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? accent.withValues(alpha: 0.4) : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 14, color: isSelected ? accent : onSurface.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isSelected ? accent : onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddEditModal({Subscription? subscription}) {
    setState(() {
      _isEditing = true;
      _editingSubscription = subscription;
    });
  }

  void _deleteSubscription(Subscription sub) {
    setState(() {
      _subscriptions.removeWhere((Subscription e) => e.id == sub.id);
      subBox.subscriptions = _subscriptions;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${sub.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            setState(() {
              _subscriptions.add(sub);
              subBox.subscriptions = _subscriptions;
            });
          },
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Screen 1: Calendar View
// ----------------------------------------------------------------------
class SubscriptionCalendarView extends StatefulWidget {
  final List<Subscription> subscriptions;
  final List<SubscriptionCategory> categories;
  final Function({Subscription? subscription}) onAddOrEdit;

  const SubscriptionCalendarView({
    super.key,
    required this.subscriptions,
    required this.categories,
    required this.onAddOrEdit,
  });

  @override
  State<SubscriptionCalendarView> createState() => _SubscriptionCalendarViewState();
}

class _SubscriptionCalendarViewState extends State<SubscriptionCalendarView> {
  DateTime _currentMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: <Widget>[
          _buildMonthHeader(),
          _buildSummaryChips(),
          Expanded(child: _buildCalendarGrid()),
          _buildFixedBottomBar(
            context: context,
            label: "Add Subscription",
            onTap: () => widget.onAddOrEdit(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    // final String monthName = _currentMonth.month.toString(); // simplistic, should use DateFormat

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            icon: Icon(Icons.chevron_left, size: 20, color: onSurface.withValues(alpha: 0.8)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
              });
            },
          ),
          Text(
            "${_getMonthName(_currentMonth.month)} ${_currentMonth.year}".toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: onSurface,
            ),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, size: 20, color: onSurface.withValues(alpha: 0.8)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChips() {
    double totalSpend = 0;
    int activeCount = 0;
    for (Subscription sub in widget.subscriptions) {
      if (sub.isActive) {
        totalSpend += sub.normalizedMonthlyAmount;
        activeCount++;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _buildChip("Spend", "\$${totalSpend.toStringAsFixed(2)}", Icons.attach_money),
          _buildChip("Active", "$activeCount", Icons.check_circle_outline),
        ],
      ),
    );
  }

  Widget _buildChip(String label, String value, IconData icon) {
    final Color accent = userSettings.themeColors.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 6),
          Text(
            "$label: $value",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final int daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final int firstDayOffset = DateTime(_currentMonth.year, _currentMonth.month, 1).weekday - 1; // 0 for Mon
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: Alignment.topCenter, // Keeps the calendar centered horizontally at the top
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 450, // Caps the width so cells don't get too big on desktop/web
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min, // Allows the column to only take needed vertical space
            children: <Widget>[
              // Weekday headers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <String>["M", "T", "W", "T", "F", "S", "S"].map((String d) {
                  return Expanded(
                    // Ensures header text aligns perfectly with grid columns
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              // Replaced Expanded with Flexible + shrinkWrap so it plays nice with ConstrainedBox
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: daysInMonth + firstDayOffset,
                  itemBuilder: (BuildContext context, int index) {
                    if (index < firstDayOffset) return const SizedBox();
                    final int day = index - firstDayOffset + 1;
                    final DateTime date = DateTime(_currentMonth.year, _currentMonth.month, day);
                    return _buildCalendarCell(date);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarCell(DateTime date) {
    final DateTime now = DateTime.now();
    final bool isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accentColor;
    final List<Subscription> subsToday = widget.subscriptions.where((Subscription s) {
      return s.isBillingOnDate(date);
    }).toList();

    return InkWell(
      onTap: subsToday.isEmpty ? null : () => _showDaySubs(date, subsToday),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          color: isToday ? accent.withValues(alpha: 0.15) : onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isToday
                ? accent.withValues(alpha: 0.5)
                : (subsToday.isNotEmpty ? accent.withValues(alpha: 0.2) : Colors.transparent),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                "${date.day}",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isToday ? accent : onSurface.withValues(alpha: 0.8),
                ),
              ),
            ),
            if (subsToday.isNotEmpty)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 3, left: 2, right: 2),
                  child: _buildCalendarCellLogos(subsToday),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCellLogos(List<Subscription> subs) {
    final Color accent = userSettings.themeColors.accentColor;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 2.0;
        const double maxAvatarSize = 16.0;
        final double availableWidth = constraints.maxWidth;

        // How many avatar slots fit at maxAvatarSize?
        final int canFit = ((availableWidth + gap) / (maxAvatarSize + gap)).floor().clamp(1, subs.length);
        final bool needsBadge = subs.length > canFit;
        final int maxVisible = needsBadge ? (canFit - 1).clamp(1, subs.length) : canFit;
        final List<Subscription> visible = subs.take(maxVisible).toList();
        final int overflow = subs.length - maxVisible;
        final int totalSlots = visible.length + (overflow > 0 ? 1 : 0);
        // Size avatars to exactly fill the available width
        final double size = ((availableWidth - gap * (totalSlots - 1)) / totalSlots).clamp(8.0, maxAvatarSize);

        Widget buildAvatar(Subscription s) => FutureBuilder<Uint8List?>(
              future:
                  AuthenticatorLogoStore.instance.getLogo(AuthenticatorEntry(id: 'dummy', secret: '', issuer: s.name)),
              builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                  return CircleAvatar(
                    radius: size / 2,
                    backgroundImage: MemoryImage(snapshot.data!),
                    backgroundColor: s.color.withValues(alpha: 0.15),
                  );
                }
                return CircleAvatar(
                  radius: size / 2,
                  backgroundColor: s.color.withValues(alpha: 0.25),
                  child: Text(
                    s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: size * 0.42, color: s.color, fontWeight: FontWeight.bold),
                  ),
                );
              },
            );

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ...visible.asMap().entries.map((MapEntry<int, Subscription> e) => Padding(
                  padding: EdgeInsets.only(left: e.key == 0 ? 0 : gap),
                  child: buildAvatar(e.value),
                )),
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.only(left: gap),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.5), width: 0.5),
                  ),
                  child: Center(
                    child: Text(
                      "+$overflow",
                      style: TextStyle(
                        fontSize: size * 0.36,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showDaySubs(DateTime date, List<Subscription> subs) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (BuildContext ctx) {
        final Color onSurface = Theme.of(context).colorScheme.onSurface;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration:
                      BoxDecoration(color: onSurface.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text("Due on ${_getMonthName(date.month)} ${date.day}",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: onSurface)),
              ),
              ...subs.map((Subscription s) => ListTile(
                    leading: FutureBuilder<Uint8List?>(
                      future: AuthenticatorLogoStore.instance
                          .getLogo(AuthenticatorEntry(id: 'dummy', secret: '', issuer: s.name)),
                      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                        if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                          return CircleAvatar(
                            backgroundColor: s.color.withValues(alpha: 0.15),
                            backgroundImage: MemoryImage(snapshot.data!),
                          );
                        }
                        return CircleAvatar(
                          backgroundColor: s.color.withValues(alpha: 0.2),
                          child: Text(
                            s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 16, color: s.color, fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                    title: Text(s.name, style: TextStyle(fontSize: 13, color: onSurface)),
                    trailing: Text("${s.amount} ${s.currency}",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: onSurface)),
                  )),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  String _getMonthName(int month) {
    const List<String> months = <String>[
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    return months[month - 1];
  }

  Widget _buildFixedBottomBar({
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
  }) {
    return Stack(
      children: <Widget>[
        Positioned(
          right: 0,
          top: 0,
          child: Text("logo.dev ", style: TextStyle(fontSize: 10, color: userSettings.themeColors.textColor)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15))),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Center(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 32),
                  decoration: BoxDecoration(
                    color: userSettings.themeColors.accentColor.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: userSettings.themeColors.accentColor.withValues(alpha: 0.8), width: 1),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: userSettings.themeColors.accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// Screen 2: Insights View
// ----------------------------------------------------------------------
class SubscriptionInsightsView extends StatefulWidget {
  final List<Subscription> subscriptions;
  final List<SubscriptionCategory> categories;
  final Function({Subscription? subscription}) onEdit;
  final Function(Subscription) onDelete;

  const SubscriptionInsightsView({
    super.key,
    required this.subscriptions,
    required this.categories,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<SubscriptionInsightsView> createState() => _SubscriptionInsightsViewState();
}

class _SubscriptionInsightsViewState extends State<SubscriptionInsightsView> {
  DateTime _selectedMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accentColor;

    double totalMonthly = 0;
    double totalYearly = 0;
    Map<String, double> catSpend = <String, double>{};

    final List<Subscription> activeSubs = widget.subscriptions.where((Subscription s) => s.isActive).toList();

    for (Subscription s in activeSubs) {
      // FIX: Check if this subscription actually has any billing occurrence
      // during the user's selected month/year carousel.
      bool billsInSelectedMonth = false;
      final int daysInMonth = DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month);

      // Loop through all days of the selected month to find an occurrence
      for (int day = 1; day <= daysInMonth; day++) {
        final DateTime checkDate = DateTime(_selectedMonth.year, _selectedMonth.month, day);
        if (s.isBillingOnDate(checkDate)) {
          billsInSelectedMonth = true;
          break; // Found an occurrence, no need to check further days
        }
      }

      // Only add to the current view metrics if it's due this month!
      if (billsInSelectedMonth) {
        final double amount = s.normalizedMonthlyAmount;
        totalMonthly += amount;
        catSpend[s.categoryId] = (catSpend[s.categoryId] ?? 0) + amount;
      }

      // Keep your overall yearly projected baseline calculation unchanged
      if (s.billingCycle == BillingCycle.monthly) {
        totalYearly += s.amount * 12;
      } else if (s.billingCycle == BillingCycle.yearly) {
        totalYearly += s.amount;
      } else if (s.billingCycle == BillingCycle.weekly) {
        totalYearly += s.amount * 52;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(14),
      children: <Widget>[
        // Month Selector Carousel
        SizedBox(
          height: 32,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 12,
            itemBuilder: (BuildContext context, int index) {
              final DateTime month = DateTime.now().subtract(Duration(days: 30 * (6 - index))); // Center around now
              final bool isSelected = _selectedMonth.month == month.month && _selectedMonth.year == month.year;

              const List<String> months = <String>[
                "Jan",
                "Feb",
                "Mar",
                "Apr",
                "May",
                "Jun",
                "Jul",
                "Aug",
                "Sep",
                "Oct",
                "Nov",
                "Dec"
              ];
              final String label = "${months[month.month - 1]} ${month.year}";

              return InkWell(
                onTap: () => setState(() => _selectedMonth = month),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? accent.withValues(alpha: 0.28) : onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isSelected ? accent.withValues(alpha: 0.8) : Colors.transparent),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? accent : onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),

        if (activeSubs.isNotEmpty) ...<Widget>[
          SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 60,
                    sections: catSpend.entries.map((MapEntry<String, double> e) {
                      // FIX: Added orElse to handle missing categories safely
                      final SubscriptionCategory cat = widget.categories.firstWhere(
                        (SubscriptionCategory c) => c.id == e.key,
                        orElse: () => widget.categories.firstWhere((SubscriptionCategory c) => c.id == 'cat_other',
                            orElse: () => widget.categories.first),
                      );
                      return PieChartSectionData(
                        color: cat.color,
                        value: e.value,
                        title: '',
                        radius: 20,
                      );
                    }).toList(),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text("Total/mo", style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.6))),
                    Text("\$${totalMonthly.toStringAsFixed(2)}",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: onSurface)),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        _buildSectionLabel("Your Subscriptions", onSurface, activeSubs.length, Icons.list),
        const SizedBox(height: 10),
        ...activeSubs.map((Subscription s) {
          // FIX: Added orElse here as well to protect the list tiles
          final SubscriptionCategory cat = widget.categories.firstWhere(
            (SubscriptionCategory c) => c.id == s.categoryId,
            orElse: () => widget.categories
                .firstWhere((SubscriptionCategory c) => c.id == 'cat_other', orElse: () => widget.categories.first),
          );
          return Dismissible(
            key: Key(s.id),
            background: Container(
              color: Colors.redAccent,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            direction: DismissDirection.endToStart,
            onDismissed: (DismissDirection direction) => widget.onDelete(s),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: onSurface.withValues(alpha: 0.16)),
              ),
              child: ListTile(
                leading: FutureBuilder<Uint8List?>(
                  future:
                      AuthenticatorLogoStore.instance.getLogo(AuthenticatorEntry(id: s.id, secret: '', issuer: s.name)),
                  builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                    if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                      return CircleAvatar(backgroundImage: MemoryImage(snapshot.data!), radius: 16);
                    }
                    return CircleAvatar(
                        backgroundColor: s.color.withValues(alpha: 0.2),
                        radius: 16,
                        child:
                            Text(s.name.substring(0, 1).toUpperCase(), style: TextStyle(color: s.color, fontSize: 12)));
                  },
                ),
                title: Text(s.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: onSurface)),
                subtitle: Row(
                  children: <Widget>[
                    Icon(IconData(cat.iconCodePoint, fontFamily: cat.fontFamily), size: 10, color: cat.color),
                    const SizedBox(width: 4),
                    Text(cat.name, style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.6))),
                    if (!s.isActive) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                        child: const Text("Inactive", style: TextStyle(fontSize: 9, color: Colors.redAccent)),
                      ),
                    ]
                  ],
                ),
                // FIX: Changed trailing from a single Text widget to a Column displaying lifetime total
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      "${s.amount} ${s.currency}",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Spent: \$${s.totalSpentToDate.formatNum()}",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                onTap: () => widget.onEdit(subscription: s),
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
        // Yearly Projection Banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.calendar_today, size: 24, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                        "Based on your active subscriptions, your estimated yearly spend is \$${totalYearly.toStringAsFixed(2)}",
                        style: TextStyle(fontSize: 12, color: onSurface)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        const Center(child: Text("Logos by logo.dev")),
      ],
    );
  }

  Widget _buildSectionLabel(String label, Color onSurface, int count, IconData icon) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: userSettings.themeColors.accentColor),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: userSettings.themeColors.accentColor.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text("$count", style: TextStyle(fontSize: 10, color: userSettings.themeColors.accentColor)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: onSurface.withValues(alpha: 0.2))),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// Subscription Form
// ----------------------------------------------------------------------
class SubscriptionForm extends StatefulWidget {
  final List<SubscriptionCategory> categories;
  final Subscription? subscription;
  final Function(Subscription) onSave;

  const SubscriptionForm({
    super.key,
    required this.categories,
    this.subscription,
    required this.onSave,
  });

  @override
  State<SubscriptionForm> createState() => _SubscriptionFormState();
}

class _SubscriptionFormState extends State<SubscriptionForm> {
  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late TextEditingController _notesController;
  late String _currency;
  late BillingCycle _billingCycle;
  late DateTime _startDate;
  late String _categoryId;
  late Color _color;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final Subscription? sub = widget.subscription;
    _nameController = TextEditingController(text: sub?.name ?? "");
    _amountController = TextEditingController(text: sub?.amount.toString() ?? "");
    _notesController = TextEditingController(text: sub?.notes ?? "");
    _currency = sub?.currency ?? "USD";
    _billingCycle = sub?.billingCycle ?? BillingCycle.monthly;
    _startDate = sub?.startDate ?? DateTime.now();
    _categoryId = sub?.categoryId ?? widget.categories.first.id;
    _color = sub?.color ?? Colors.blueAccent;
    _isActive = sub?.isActive ?? true;
    _updateLogoPreview();

    _nameController.addListener(() {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          _updateLogoPreview();
        }
      });
    });
  }

  void _updateLogoPreview() {
    final String text = _nameController.text.trim();
    if (text.isNotEmpty) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.isEmpty || _amountController.text.isEmpty) return;

    final Subscription sub = Subscription(
      id: widget.subscription?.id ?? const Uuid().v4(),
      name: _nameController.text,
      logoUrl: "",
      amount: double.tryParse(_amountController.text) ?? 0,
      currency: _currency,
      billingCycle: _billingCycle,
      startDate: _startDate,
      categoryId: _categoryId,
      color: _color,
      notes: _notesController.text,
      isActive: _isActive,
    );
    widget.onSave(sub);
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accentColor;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: WindowsScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CustomTextField(
                labelText: "Service Name",
                onChanged: (String e) {
                  _nameController.text = e;
                },
                value: _nameController.text,
                icon: _nameController.text.isNotEmpty
                    ? FutureBuilder<Uint8List?>(
                        future: AuthenticatorLogoStore.instance
                            .getLogo(AuthenticatorEntry(id: 'dummy', secret: '', issuer: _nameController.text)),
                        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                          if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: CircleAvatar(
                                backgroundImage: MemoryImage(snapshot.data!),
                                radius: 12,
                              ),
                            );
                          }
                          return const Icon(Icons.business, size: 20);
                        },
                      )
                    : const Icon(Icons.business, size: 20),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: CustomTextField(
                      onChanged: (String e) {
                        _amountController.text = e;
                      },
                      value: _amountController.text,
                      labelText: "Amount",
                      iconData: Icons.currency_exchange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ModernDropdown<String>(
                      value: _currency,
                      prefixIcon: const Icon(Icons.currency_exchange_sharp, size: 12),
                      isExpanded: false,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withAlpha(30)),
                      ),
                      items: <String>["USD", "EUR", "GBP", "RON", "JPY", "CAD", "AUD"].map((String c) {
                        return ModernDropdownItem<String>(value: c, label: c);
                      }).toList(),
                      onChanged: (String? v) => setState(() => _currency = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ModernDropdown<BillingCycle>(
                value: _billingCycle,
                isExpanded: false,
                height: 38,
                prefixIcon: const Icon(Icons.calendar_month),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withAlpha(30)),
                ),
                items: BillingCycle.values.map((BillingCycle b) {
                  return ModernDropdownItem<BillingCycle>(value: b, label: b.name.toUpperCase());
                }).toList(),
                onChanged: (BillingCycle? v) => setState(() => _billingCycle = v!),
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 10),
              Material(
                type: MaterialType.transparency,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final DateTime? dt = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            barrierColor: Colors.transparent,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (dt != null) setState(() => _startDate = dt);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Text(
                            "Start Date: ${_startDate.year}-${_startDate.month}-${_startDate.day}",
                            style: TextStyle(color: onSurface, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ModernDropdown<String>(
                        value: _categoryId,
                        isExpanded: false,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withAlpha(30)),
                        ),
                        items: widget.categories.map((SubscriptionCategory c) {
                          return ModernDropdownItem<String>(value: c.id, label: c.name);
                        }).toList(),
                        onChanged: (String? v) => setState(() => _categoryId = v!),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <MaterialAccentColor>[
                    Colors.blueAccent,
                    Colors.redAccent,
                    Colors.greenAccent,
                    Colors.purpleAccent,
                    Colors.orangeAccent,
                    Colors.amberAccent,
                    Colors.pinkAccent,
                    Colors.cyanAccent
                  ].map((MaterialAccentColor c) {
                    return InkWell(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? onSurface : Colors.transparent, width: 2),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              CustomTextField(
                value: _notesController.text,
                onChanged: (String e) {
                  _notesController.text = e;
                },
                labelText: "Notes (Optional)",
                iconData: Icons.note_alt,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                title: Text("Active", style: TextStyle(fontSize: 13, color: onSurface)),
                value: _isActive,
                onChanged: (bool v) => setState(() => _isActive = v),
                activeTrackColor: accent.withValues(alpha: 0.5),
                activeThumbColor: accent,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),
              Center(
                child: InkWell(
                  onTap: _save,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 40),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withValues(alpha: 0.8)),
                    ),
                    child: Text(
                      "SAVE",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
