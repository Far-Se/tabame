import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/settings.dart';

class TrktivityHeatMap extends StatefulWidget {
  final List<String> allDates;
  final String folder;

  const TrktivityHeatMap({super.key, required this.allDates, required this.folder});

  @override
  TrktivityHeatMapState createState() => TrktivityHeatMapState();
}

class TrktivityHeatMapState extends State<TrktivityHeatMap> {
  final Map<String, int> heatData = <String, int>{};
  int maxKeys = 0;
  List<DateTime> displayDays = <DateTime>[];

  // Each entry: one week = list of 7 DateTimes (Mon–Sun), nulls for padding
  List<List<DateTime?>> weeks = <List<DateTime?>>[];
  // Per-week-column index: month label (null = no label for that column)
  List<String?> weekMonthLabels = <String?>[];

  bool isLoading = true;
  int? selectedDaysRange = 365; // null means "All"

  static const double cellSize = 14.0;
  static const double cellSpacing = 3.0;
  static const double dayLabelWidth = 28.0;
  static const double monthRowHeight = 16.0;

  // Scroll controller shared between month label row and grid rows
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadHeatMap();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double get _columnWidth => cellSize + cellSpacing;

  void _buildWeeks() {
    DateTime today = DateTime.now();
    today = DateTime(today.year, today.month, today.day);

    DateTime firstDay;
    if (selectedDaysRange == null) {
      if (widget.allDates.isNotEmpty) {
        List<String> sorted = List<String>.from(widget.allDates)..sort();
        try {
          firstDay = DateFormat("yyyy-MM-dd").parse(sorted.first);
        } catch (e) {
          firstDay = today.subtract(const Duration(days: 364));
        }
      } else {
        firstDay = today.subtract(const Duration(days: 364));
      }
    } else {
      firstDay = today.subtract(Duration(days: selectedDaysRange! - 1));
    }

    // Align to Monday
    while (firstDay.weekday != DateTime.monday) {
      firstDay = firstDay.subtract(const Duration(days: 1));
    }

    displayDays.clear();
    DateTime current = firstDay;
    while (!current.isAfter(today)) {
      displayDays.add(current);
      current = current.add(const Duration(days: 1));
    }

    weeks.clear();
    weekMonthLabels.clear();

    for (int i = 0; i < displayDays.length; i += 7) {
      List<DateTime?> week = <DateTime?>[];
      for (int j = i; j < i + 7; j++) {
        week.add(j < displayDays.length ? displayDays[j] : null);
      }
      weeks.add(week);

      DateTime? monday = week[0];
      if (monday != null) {
        if (weeks.length == 1) {
          weekMonthLabels.add(DateFormat("MMM").format(monday));
        } else {
          DateTime? prevMonday = weeks[weeks.length - 2][0];
          if (prevMonday == null || prevMonday.month != monday.month) {
            weekMonthLabels.add(DateFormat("MMM").format(monday));
          } else {
            weekMonthLabels.add(null);
          }
        }
      } else {
        weekMonthLabels.add(null);
      }
    }
  }

  /// Scroll to the rightmost position so today is visible.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadHeatMap() async {
    setState(() {
      isLoading = true;
      heatData.clear();
      maxKeys = 0;
    });
    _buildWeeks();
    if (mounted) setState(() {});

    File f = File("${widget.folder}/cumulative.json");
    Map<String, dynamic> cumulative = <String, dynamic>{};
    if (f.existsSync()) {
      try {
        cumulative = jsonDecode(f.readAsStringSync());
      } catch (e) {
        cumulative = <String, dynamic>{};
      }
      for (DateTime day in displayDays) {
        String fileName = DateFormat("yyyy-MM-dd").format(day);
        if (cumulative.containsKey(fileName)) {
          heatData[fileName] = cumulative[fileName];
          if ((cumulative[fileName] as int) > maxKeys) maxKeys = cumulative[fileName];
        } else {
          heatData[fileName] = 0;
        }
      }
    }

    // Sort displayDays to load from newest to oldest for better UX (optional, but current logic handles it fine)
    for (DateTime day in displayDays.reversed) {
      String fileName = DateFormat("yyyy-MM-dd").format(day);
      if ((heatData[fileName] ?? 0) != 0) continue;
      await Future<void>.delayed(Duration.zero);

      if (widget.allDates.contains(fileName)) {
        File dayFile = File("${widget.folder}\\$fileName.json");
        if (dayFile.existsSync()) {
          int keys = 0;
          List<String> lines = await dayFile.readAsLines();
          for (String line in lines) {
            if (line.isEmpty) continue;
            try {
              Map<String, dynamic> info = jsonDecode(line);
              if (info["t"] == "k") {
                keys += int.parse(info["d"].toString());
              }
            } catch (e) {
              // ignore
            }
          }
          heatData[fileName] = keys;
          if (keys > maxKeys) maxKeys = keys;
          cumulative[fileName] = keys;
        } else {
          heatData[fileName] = 0;
        }
      } else {
        heatData[fileName] = 0;
      }
    }

    cumulative.remove(DateFormat("yyyy-MM-dd").format(DateTime.now()));
    f.writeAsStringSync(jsonEncode(cumulative));

    if (mounted) {
      setState(() {
        isLoading = false;
      });
      _scrollToEnd();
    }
  }

  Color _cellColor(BuildContext context, String dateKey) {
    int keys = heatData[dateKey] ?? 0;
    if (keys == 0) {
      return Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    }
    double intensity = maxKeys > 0 ? keys / maxKeys : 0.0;
    return Theme.of(context).colorScheme.primary.withValues(alpha: 0.2 + (0.8 * intensity));
  }

  /// Builds the scrollable month label row, driven by the same [_scrollController].
  /// Uses a [ValueListenableBuilder] on the scroll offset so labels stay
  /// visually "pinned" — the row scrolls with the grid but we clip it to the
  /// viewport and offset the inner content by the scroll amount, making labels
  /// appear sticky relative to the viewport.
  Widget _buildStickyMonthRow(double viewportWidth) {
    return SizedBox(
      height: monthRowHeight,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _scrollController,
          builder: (BuildContext context, Widget? _) {
            double offset = _scrollController.hasClients ? _scrollController.offset : 0.1;

            // Find which month labels are visible in the current viewport.
            // For each label, compute its "natural" X position (as if unscrolled)
            // then subtract offset to get screen X. If a label would overlap the
            // next label, we push it to the left edge of the visible month range.
            List<Widget> labels = <Widget>[];

            for (int col = 0; col < weeks.length; col++) {
              String? label = weekMonthLabels[col];
              if (label == null) continue;

              double naturalX = col * _columnWidth - offset;

              // Find where this month ends (next label column or end)
              int nextLabelCol = weeks.length;
              for (int nc = col + 1; nc < weeks.length; nc++) {
                if (weekMonthLabels[nc] != null) {
                  nextLabelCol = nc;
                  break;
                }
              }
              double monthEndX = nextLabelCol * _columnWidth - offset;

              // Clamp label so it sticks to left edge of its visible month range
              double labelX = naturalX;

              // Only render if within viewport
              if (labelX > viewportWidth || monthEndX < 0) continue;

              labels.add(Positioned(
                left: labelX,
                top: 0,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ));
            }

            return Stack(children: labels);
          },
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, DateTime? day) {
    if (day == null) {
      return const SizedBox(width: cellSize, height: cellSize);
    }
    if (isLoading) {
      return Container(
        width: cellSize,
        height: cellSize,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    String dateKey = DateFormat("yyyy-MM-dd").format(day);
    int keys = heatData[dateKey] ?? 0;
    final bool isFirstOfMonth = day.day == 1;

    Widget cell = Container(
      width: cellSize,
      height: cellSize,
      decoration: BoxDecoration(
        color: _cellColor(context, dateKey),
        borderRadius: BorderRadius.circular(3),
        border: isFirstOfMonth
            ? Border.all(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                width: 1,
              )
            : null,
      ),
    );
    return Tooltip(message: "${DateFormat("MMM dd, yyyy").format(day)}\n${keys.formatNum()} keypresses", ignorePointer: true, child: cell);
  }

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) return const SizedBox();

    const List<String> dayLabels = <String>["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text("Activity Heatmap", style: Theme.of(context).textTheme.titleMedium),
            DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: selectedDaysRange,
                isDense: true,
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(value: 30, child: Text("Last 30 Days", style: TextStyle(fontSize: 12))),
                  const DropdownMenuItem<int?>(value: 90, child: Text("Last 90 Days", style: TextStyle(fontSize: 12))),
                  const DropdownMenuItem<int?>(value: 180, child: Text("Last 180 Days", style: TextStyle(fontSize: 12))),
                  const DropdownMenuItem<int?>(value: 365, child: Text("Last Year", style: TextStyle(fontSize: 12))),
                  const DropdownMenuItem<int?>(value: null, child: Text("All Time", style: TextStyle(fontSize: 12))),
                ],
                onChanged: (int? newValue) {
                  setState(() {
                    selectedDaysRange = newValue;
                  });
                  _loadHeatMap();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double availableWidth = constraints.maxWidth;
            final double gridViewportWidth = availableWidth - dayLabelWidth;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // ── Sticky month row ─────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(width: dayLabelWidth), // aligns with day labels
                    Expanded(child: _buildStickyMonthRow(gridViewportWidth)),
                  ],
                ),
                const SizedBox(height: 4),
                // ── Day label column + scrollable grid ───────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Fixed day-of-week labels (not scrollable)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List<Widget>.generate(7, (int row) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: cellSpacing),
                          child: SizedBox(
                            width: dayLabelWidth,
                            height: cellSize,
                            child: Text(
                              dayLabels[row],
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    // Scrollable grid
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List<Widget>.generate(7, (int row) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: cellSpacing),
                              child: Row(
                                children: <Widget>[
                                  ...List<Widget>.generate(weeks.length, (int col) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: cellSpacing),
                                      child: _buildCell(context, weeks[col][row]),
                                    );
                                  }),
                                  const SizedBox(width: 20),
                                ],
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // ── Legend ───────────────────────────────────────────────────
                Row(
                  children: <Widget>[
                    const SizedBox(width: dayLabelWidth),
                    const Text("Less", style: TextStyle(fontSize: 9, color: Colors.grey)),
                    const SizedBox(width: 4),
                    ...List<Widget>.generate(5, (int i) {
                      Color color = i == 0
                          ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2 + (0.8 * (i / 4)));
                      return Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                        ),
                      );
                    }),
                    const SizedBox(width: 4),
                    const Text("More", style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
