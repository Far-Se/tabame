import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/quick_menu_panel.dart';

class TimeZoneButton extends StatelessWidget {
  const TimeZoneButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Time Zone", icon: const Icon(Icons.public_rounded), child: () => const TimeZoneWidget());
  }
}

class TimeZoneWidget extends StatefulWidget {
  const TimeZoneWidget({super.key});

  @override
  State<TimeZoneWidget> createState() => _TimeZoneWidgetState();
}

class _TimeZoneWidgetState extends State<TimeZoneWidget> {
  static const String _zonesKey = "meetingTimeZones";
  static const String _timeInputKey = "meetingTimeInput";
  static const List<String> _defaultZones = <String>[
    "America/New_York",
    "Europe/London",
    "Asia/Tokyo",
  ];

  static bool _timezoneInitialized = false;

  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  late List<String> _selectedZones;
  List<String> _allZones = <String>[];
  bool _settingsMode = false;

  @override
  void initState() {
    super.initState();
    _ensureTimezoneDatabase();
    _selectedZones = _loadSavedZones();
    _timeController.text =
        Boxes.pref.getString(_timeInputKey) ?? _formatCompactTime(TimeOfDay.fromDateTime(DateTime.now()));
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final TimeOfDay? parsedTime = _parseTimeInput(_timeController.text);

    return QuickMenuPanel(
      title: _settingsMode ? "Time Zone Settings" : "Time Zone",
      accent: accent,
      icon: _settingsMode ? Icons.settings_rounded : Icons.public_rounded,
      buttonPressed: () {
        setState(() {
          _settingsMode = !_settingsMode;
        });
      },
      buttonIcon: _settingsMode ? Icons.schedule_rounded : Icons.settings_outlined,
      useMouseScroll: true,
      body: _settingsMode ? _buildSettingsView(accent, onSurface) : _buildPlannerView(accent, onSurface, parsedTime),
    );
  }

  Widget _buildPlannerView(Color accent, Color onSurface, TimeOfDay? parsedTime) {
    final DateTime now = DateTime.now();
    final String localZone = now.timeZoneName.isEmpty ? "Local" : now.timeZoneName;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withAlpha(10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Type a local wall-clock time like 6 PM or 18:30 and compare it with saved zones.",
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    color: onSurface.withAlpha(180),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _timeController,
                  onChanged: (String value) {
                    Boxes.updateSettings(_timeInputKey, value.trim());
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: "6 PM",
                    filled: true,
                    fillColor: accent.withAlpha(14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    prefixIcon: Icon(Icons.schedule_rounded, size: 16, color: accent),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accent.withAlpha(90), width: 1),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _buildMiniChip("Local zone: $localZone", accent, onSurface),
                    _buildMiniChip(DateFormat("EEE, d MMM").format(now), accent, onSurface),
                    _buildMiniChip("DST aware", accent, onSurface),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (parsedTime == null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Use formats like 6 PM, 6:30 pm, 18:00, or 0830.",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  color: onSurface.withAlpha(190),
                ),
              ),
            )
          else if (_selectedZones.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: accent.withAlpha(10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "No zones saved yet. Open settings and add the time zones you talk to most.",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  color: onSurface.withAlpha(190),
                ),
              ),
            )
          else
            ..._selectedZones.map((String zoneId) => _buildZoneCard(zoneId, parsedTime, accent, onSurface)),
        ],
      ),
    );
  }

  Widget _buildSettingsView(Color accent, Color onSurface) {
    final List<String> results = _filteredZoneResults();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: "Search a city or zone, like New York or Tokyo",
              filled: true,
              fillColor: accent.withAlpha(10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: Icon(Icons.travel_explore_rounded, size: 16, color: accent),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: accent.withAlpha(90), width: 1),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Saved zones",
            style: TextStyle(
              fontSize: Design.baseFontSize + 2,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 6),
          if (_selectedZones.isEmpty)
            Text(
              "No saved zones yet.",
              style: TextStyle(
                fontSize: Design.baseFontSize + 2,
                color: onSurface.withAlpha(150),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _selectedZones
                  .map(
                    (String zone) => Container(
                      padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _shortZoneLabel(zone),
                            style: TextStyle(
                              fontSize: Design.baseFontSize + 2,
                              color: onSurface.withAlpha(210),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => _removeZone(zone),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(Icons.close_rounded, size: 14, color: onSurface.withAlpha(150)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 12),
          Text(
            "Add zone",
            style: TextStyle(
              fontSize: Design.baseFontSize + 2,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 6),
          if (results.isEmpty)
            Text(
              "No matching zones found.",
              style: TextStyle(
                fontSize: Design.baseFontSize + 2,
                color: onSurface.withAlpha(150),
              ),
            )
          else
            ...results.map(
              (String zone) => InkWell(
                onTap: () => _addZone(zone),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.add_circle_outline_rounded, size: 15, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _prettyZoneName(zone),
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 2,
                            color: onSurface.withAlpha(210),
                          ),
                        ),
                      ),
                      Text(
                        zone,
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          color: onSurface.withAlpha(120),
                        ),
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

  Widget _buildZoneCard(String zoneId, TimeOfDay parsedTime, Color accent, Color onSurface) {
    final tz.Location location = tz.getLocation(zoneId);
    final DateTime now = DateTime.now();
    final DateTime localTime = DateTime(now.year, now.month, now.day, parsedTime.hour, parsedTime.minute);
    final tz.TZDateTime thereAtMyTime = tz.TZDateTime.from(localTime, location);
    final tz.TZDateTime theirSameWallClock =
        tz.TZDateTime(location, now.year, now.month, now.day, parsedTime.hour, parsedTime.minute);
    final DateTime hereAtTheirTime = theirSameWallClock.toLocal();
    final String myTimeLabel = _formatDateTime(localTime);
    final String thereAtMyTimeLabel = _formatDateTime(thereAtMyTime);
    final String theirTimeLabel = _formatDateTime(theirSameWallClock);
    final String hereAtTheirTimeLabel = _formatDateTime(hereAtTheirTime);
    final String offsetLabel = _formatOffset(tz.TZDateTime.now(location).timeZoneOffset);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _prettyZoneName(zoneId),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                ),
              ),
              Text(
                offsetLabel,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  color: onSurface.withAlpha(145),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            zoneId,
            style: TextStyle(
              fontSize: Design.baseFontSize + 1,
              color: onSurface.withAlpha(125),
            ),
          ),
          const SizedBox(height: 8),
          _buildResultLine(
            accent: accent,
            onSurface: onSurface,
            title: "$myTimeLabel here is",
            result: "$thereAtMyTimeLabel in ${_shortZoneLabel(zoneId)}",
          ),
          const SizedBox(height: 6),
          _buildResultLine(
            accent: accent,
            onSurface: onSurface,
            title: "$theirTimeLabel in ${_shortZoneLabel(zoneId)} is",
            result: "$hereAtTheirTimeLabel here",
          ),
        ],
      ),
    );
  }

  Widget _buildResultLine({
    required Color accent,
    required Color onSurface,
    required String title,
    required String result,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 4,
          height: 32,
          margin: const EdgeInsets.only(top: 1, right: 8),
          decoration: BoxDecoration(
            color: accent.withAlpha(150),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withAlpha(180),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                result,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withAlpha(180),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniChip(String label, Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Design.baseFontSize + 1,
          color: onSurface.withAlpha(170),
        ),
      ),
    );
  }

  void _ensureTimezoneDatabase() {
    if (!_timezoneInitialized) {
      tzdata.initializeTimeZones();
      _timezoneInitialized = true;
    }
    _allZones = tz.timeZoneDatabase.locations.keys.toList()..sort();
  }

  List<String> _loadSavedZones() {
    final List<String> saved = Boxes.pref.getStringList(_zonesKey) ?? _defaultZones;
    return saved.toSet().toList();
  }

  List<String> _filteredZoneResults() {
    if (_allZones.isEmpty) {
      _allZones = tz.timeZoneDatabase.locations.keys.toList()..sort();
    }
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return <String>[];
      //   return _allZones.where((String zone) => !_selectedZones.contains(zone)).take(14).toList();
    }
    return _allZones
        .where((String zone) => !_selectedZones.contains(zone))
        .where((String zone) {
          final String normalized = zone.toLowerCase().replaceAll('_', ' ');
          return normalized.contains(query);
        })
        .take(20)
        .toList();
  }

  void _addZone(String zone) {
    if (_selectedZones.contains(zone)) return;
    setState(() {
      _selectedZones.add(zone);
    });
    Boxes.updateSettings(_zonesKey, _selectedZones);
  }

  void _removeZone(String zone) {
    setState(() {
      _selectedZones.remove(zone);
    });
    Boxes.updateSettings(_zonesKey, _selectedZones);
  }

  TimeOfDay? _parseTimeInput(String raw) {
    final String input = raw.trim().toLowerCase();
    if (input.isEmpty) return null;

    final RegExp compact = RegExp(r'^(\d{1,2})(?::?(\d{2}))?\s*([ap]m)?$');
    final Match? match = compact.firstMatch(input.replaceAll('.', ''));
    if (match == null) return null;

    int hour = int.tryParse(match.group(1) ?? '') ?? -1;
    final int minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    final String meridian = match.group(3) ?? '';

    if (minute < 0 || minute > 59) return null;

    if (meridian.isNotEmpty) {
      if (hour < 1 || hour > 12) return null;
      if (meridian == 'pm' && hour != 12) hour += 12;
      if (meridian == 'am' && hour == 12) hour = 0;
    } else if (hour > 23 || hour < 0) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatCompactTime(TimeOfDay time) {
    return _formatTimeOfDay(time);
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final DateTime sample = DateTime(2000, 1, 1, time.hour, time.minute);
    return DateFormat('h:mm a').format(sample);
  }

  String _formatDateTime(DateTime value) {
    return "${DateFormat('h:mm a').format(value)} ${_relativeDay(value)}";
  }

  String _relativeDay(DateTime value) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(value.year, value.month, value.day);
    final int diff = day.difference(today).inDays;
    if (diff == 0) return "today";
    if (diff == 1) return "tomorrow";
    if (diff == -1) return "yesterday";
    return DateFormat('EEE').format(value);
  }

  String _formatOffset(Duration offset) {
    final String sign = offset.isNegative ? "-" : "+";
    final Duration absolute = offset.abs();
    final String hours = absolute.inHours.toString().padLeft(2, '0');
    final String minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
    return "GMT$sign$hours:$minutes";
  }

  String _shortZoneLabel(String zoneId) {
    final List<String> parts = zoneId.split('/');
    if (parts.isEmpty) return zoneId;
    return parts.last.replaceAll('_', ' ');
  }

  String _prettyZoneName(String zoneId) {
    final List<String> parts = zoneId.split('/');
    if (parts.length == 1) return zoneId.replaceAll('_', ' ');
    return parts.map((String part) => part.replaceAll('_', ' ')).join(" • ");
  }
}
