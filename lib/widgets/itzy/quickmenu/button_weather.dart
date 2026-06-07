import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/quick_menu_panel.dart';

class WeatherButton extends StatelessWidget {
  const WeatherButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Weather",
      icon: const Icon(Icons.wb_cloudy_rounded),
      heightFactor: 0.9,
      child: () => const WeatherPanel(),
    );
  }
}

class WeatherPanel extends StatefulWidget {
  const WeatherPanel({super.key});

  @override
  State<WeatherPanel> createState() => _WeatherPanelState();
}

class _WeatherPanelState extends State<WeatherPanel> {
  static const String _locationsKey = "weatherLocations";

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _detailScrollController = ScrollController();
  final GlobalKey _currentHourKey = GlobalKey();
  final Map<String, _WeatherForecast> _forecastCache = <String, _WeatherForecast>{};
  final Set<String> _loadingForecasts = <String>{};
  final Set<String> _failedForecasts = <String>{};

  List<_WeatherLocation> _locations = <_WeatherLocation>[];
  List<_LocationSearchResult> _searchResults = <_LocationSearchResult>[];
  _WeatherLocation? _selectedLocation;
  _WeatherTab _tab = _WeatherTab.today;
  _WeatherMode _mode = _WeatherMode.overview;
  bool _searching = false;
  String? _searchError;
  String? _lastCenteredHourId;
  int _searchToken = 0;
  int _forecastToken = 0;

  @override
  void initState() {
    super.initState();
    _locations = _loadLocations();
    unawaited(_refreshForecasts());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return QuickMenuPanel(
      title: _title,
      accent: accent,
      icon: _mode == _WeatherMode.detail ? Icons.location_on_rounded : Icons.wb_cloudy_rounded,
      buttonPressed: _headerAction,
      buttonIcon: _mode == _WeatherMode.overview ? Icons.tune_rounded : Icons.arrow_back_rounded,
      buttonTooltip: _mode == _WeatherMode.overview ? "Manage locations" : "Back",
      extraActions: <Widget>[
        IconButton(
          onPressed: _mode == _WeatherMode.overview ? () => unawaited(_refreshForecasts(force: true)) : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          iconSize: 14,
          icon: Icon(
            Icons.refresh_rounded,
            color: _mode == _WeatherMode.overview ? accent : onSurface.withAlpha(60),
          ),
        ),
      ],
      body: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            const SingleActivator(LogicalKeyboardKey.backspace): VoidCallbackIntent(() {
              if (_mode == _WeatherMode.detail) {
                setState(() {
                  _mode = _WeatherMode.overview;
                  _selectedLocation = null;
                });
              }
            }),
          },
          includeSemantics: false,
          child: Focus(autofocus: true, focusNode: FocusNode()..requestFocus(), child: _buildBody(accent, onSurface))),
    );
  }

  String get _title {
    switch (_mode) {
      case _WeatherMode.overview:
        return "Weather";
      case _WeatherMode.manage:
        return "Weather Locations";
      case _WeatherMode.detail:
        return _selectedLocation?.displayName ?? "Weather";
    }
  }

  void _headerAction() {
    setState(() {
      if (_mode == _WeatherMode.overview) {
        _mode = _WeatherMode.manage;
      } else {
        _mode = _WeatherMode.overview;
        _selectedLocation = null;
      }
    });
  }

  Widget _buildBody(Color accent, Color onSurface) {
    switch (_mode) {
      case _WeatherMode.overview:
        return _buildOverview(accent, onSurface);
      case _WeatherMode.manage:
        return _buildManageLocations(accent, onSurface);
      case _WeatherMode.detail:
        return _buildDetail(accent, onSurface);
    }
  }

  Widget _buildOverview(Color accent, Color onSurface) {
    if (_locations.isEmpty) {
      return _buildEmptyState(
        accent: accent,
        onSurface: onSurface,
        icon: Icons.add_location_alt_rounded,
        title: "No locations saved",
        message: "Open location settings and add the places you check most.",
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        for (final _WeatherLocation location in _locations)
          _buildOverviewCard(
            location: location,
            forecast: _forecastCache[location.id],
            loading: _loadingForecasts.contains(location.id),
            failed: _failedForecasts.contains(location.id),
            accent: accent,
            onSurface: onSurface,
          ),
      ],
    );
  }

  Widget _buildOverviewCard({
    required _WeatherLocation location,
    required _WeatherForecast? forecast,
    required bool loading,
    required bool failed,
    required Color accent,
    required Color onSurface,
  }) {
    final _WeatherCondition? current = forecast?.current;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(18)),
      ),
      child: InkWell(
        onTap: forecast == null
            ? null
            : () {
                setState(() {
                  _selectedLocation = location;
                  _mode = _WeatherMode.detail;
                  _tab = _WeatherTab.today;
                  _lastCenteredHourId = null;
                });
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withAlpha(16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  current == null ? Icons.cloud_queue_rounded : _weatherIcon(current.weatherCode),
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            location.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: onSurface,
                            ),
                          ),
                        ),
                        if (loading)
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: accent,
                            ),
                          )
                        else
                          Icon(Icons.chevron_right_rounded, size: 17, color: onSurface.withAlpha(115)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (failed)
                      Text(
                        "Could not load weather.",
                        style: TextStyle(fontSize: Design.baseFontSize + 2, color: Colors.redAccent.withAlpha(220)),
                      )
                    else if (current == null)
                      Text(
                        loading ? "Loading forecast..." : "No forecast loaded yet.",
                        style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(145)),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: <Widget>[
                          _buildMetricChip(_formatTemp(current.temperature), accent, onSurface),
                          _buildMetricChip("Feels like ${_formatTemp(current.apparentTemperature)}", accent, onSurface),
                          _buildMetricChip(_weatherLabel(current.weatherCode), accent, onSurface),
                          _buildMetricChip("Wind ${_formatSpeed(current.windSpeed)}", accent, onSurface),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManageLocations(Color accent, Color onSurface) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => unawaited(_searchLocations()),
          decoration: InputDecoration(
            isDense: true,
            hintText: "Search city, region, or country",
            filled: true,
            fillColor: accent.withAlpha(10),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            prefixIcon: Icon(Icons.travel_explore_rounded, size: 16, color: accent),
            suffixIcon: IconButton(
              onPressed: _searching ? null : () => unawaited(_searchLocations()),
              icon: _searching
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
                    )
                  : Icon(Icons.search_rounded, size: 16, color: accent),
            ),
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
        if (_searchError != null) ...<Widget>[
          const SizedBox(height: 8),
          _buildMessageStrip(_searchError!, Colors.redAccent, onSurface),
        ],
        if (_searchResults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          _buildSectionLabel("Search results", onSurface),
          const SizedBox(height: 6),
          for (final _LocationSearchResult result in _searchResults) _buildSearchResultRow(result, accent, onSurface),
        ],
        const SizedBox(height: 12),
        _buildSectionLabel("Saved locations", onSurface),
        const SizedBox(height: 6),
        if (_locations.isEmpty)
          Text(
            "No saved locations yet.",
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(145)),
          )
        else
          for (int index = 0; index < _locations.length; index++) _buildSavedLocationRow(index, accent, onSurface),
      ],
    );
  }

  Widget _buildSearchResultRow(_LocationSearchResult result, Color accent, Color onSurface) {
    final bool alreadySaved = _locations.any((_WeatherLocation location) => location.matches(result));

    return InkWell(
      onTap: alreadySaved ? null : () => _addLocation(result),
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(
              alreadySaved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              size: 16,
              color: alreadySaved ? onSurface.withAlpha(110) : accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    result.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(135)),
                  ),
                ],
              ),
            ),
            Text(
              "${result.latitude.toStringAsFixed(2)}, ${result.longitude.toStringAsFixed(2)}",
              style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withAlpha(105)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedLocationRow(int index, Color accent, Color onSurface) {
    final _WeatherLocation location = _locations[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.drag_indicator_rounded, size: 16, color: onSurface.withAlpha(90)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  location.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  "${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withAlpha(120)),
                ),
              ],
            ),
          ),
          _buildIconAction(
            icon: Icons.keyboard_arrow_up_rounded,
            enabled: index > 0,
            accent: accent,
            onSurface: onSurface,
            onTap: () => _moveLocation(index, index - 1),
          ),
          _buildIconAction(
            icon: Icons.keyboard_arrow_down_rounded,
            enabled: index < _locations.length - 1,
            accent: accent,
            onSurface: onSurface,
            onTap: () => _moveLocation(index, index + 1),
          ),
          _buildIconAction(
            icon: Icons.close_rounded,
            enabled: true,
            accent: Colors.redAccent,
            onSurface: onSurface,
            onTap: () => _removeLocation(location),
          ),
        ],
      ),
    );
  }

  Widget _buildIconAction({
    required IconData icon,
    required bool enabled,
    required Color accent,
    required Color onSurface,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? accent.withAlpha(210) : onSurface.withAlpha(55),
        ),
      ),
    );
  }

  Widget _buildDetail(Color accent, Color onSurface) {
    final _WeatherLocation? location = _selectedLocation;
    final _WeatherForecast? forecast = location == null ? null : _forecastCache[location.id];

    if (location == null || forecast == null) {
      return _buildEmptyState(
        accent: accent,
        onSurface: onSurface,
        icon: Icons.cloud_off_rounded,
        title: "No forecast available",
        message: "Go back and refresh the location list.",
      );
    }

    if (_tab == _WeatherTab.today) {
      _scheduleCurrentHourCenter(location, forecast);
    }

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): VoidCallbackIntent(
          () {
            _detailScrollController.animateTo(
              _detailScrollController.offset + 30,
              duration: const Duration(milliseconds: 50),
              curve: Curves.easeOut,
            );
          },
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): VoidCallbackIntent(
          () {
            _detailScrollController.animateTo(
              _detailScrollController.offset - 30,
              duration: const Duration(milliseconds: 50),
              curve: Curves.easeOut,
            );
          },
        ),
      },
      includeSemantics: false,
      child: Focus(
        autofocus: true,
        focusNode: FocusNode()..requestFocus(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildCurrentSummary(forecast, accent, onSurface),
                  const SizedBox(height: 10),
                  _buildTabSelector(accent, onSurface),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _detailScrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: _tab == _WeatherTab.today
                    ? forecast.hourly
                        .map(
                          (WeatherHour hour) => _buildHourRow(
                            hour,
                            accent,
                            onSurface,
                            _isCurrentHour(hour, forecast),
                          ),
                        )
                        .toList()
                    : forecast.daily.map((WeatherDay day) => _buildDayRow(day, accent, onSurface)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentSummary(_WeatherForecast forecast, Color accent, Color onSurface) {
    final _WeatherCondition current = forecast.current;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(35)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_weatherIcon(current.weatherCode), color: accent, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _formatTemp(current.temperature),
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, height: 1, color: onSurface),
                ),
                const SizedBox(height: 5),
                Text(
                  "${_weatherLabel(current.weatherCode)}  Feels ${_formatTemp(current.apparentTemperature)}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(155)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                "Humidity ${current.humidity.round()}%",
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(145)),
              ),
              const SizedBox(height: 4),
              Text(
                "Wind ${_formatSpeed(current.windSpeed)}",
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(145)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          _buildTabButton("Today", _WeatherTab.today, accent, onSurface),
          _buildTabButton("Daily", _WeatherTab.daily, accent, onSurface),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, _WeatherTab tab, Color accent, Color onSurface) {
    final bool selected = _tab == tab;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _tab = tab;
          if (tab == _WeatherTab.today) {
            _lastCenteredHourId = null;
          }
        }),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(32) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Design.baseFontSize + 2,
              fontWeight: FontWeight.w700,
              color: selected ? onSurface : onSurface.withAlpha(135),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHourRow(WeatherHour hour, Color accent, Color onSurface, bool isCurrent) {
    return _buildForecastRow(
      key: isCurrent ? _currentHourKey : null,
      accent: accent,
      onSurface: onSurface,
      icon: _weatherIcon(hour.weatherCode),
      title: DateFormat("h a").format(hour.time),
      subtitle: isCurrent ? "Now  ${_weatherLabel(hour.weatherCode)}" : _weatherLabel(hour.weatherCode),
      primary: _formatTemp(hour.temperature),
      trailing: "${hour.precipitationProbability.round()}% rain  ${_formatSpeed(hour.windSpeed)}",
      highlighted: isCurrent,
    );
  }

  Widget _buildDayRow(WeatherDay day, Color accent, Color onSurface) {
    return _buildForecastRow(
      accent: accent,
      onSurface: onSurface,
      icon: _weatherIcon(day.weatherCode),
      title: DateFormat("EEE, MMM d").format(day.date),
      subtitle: "${_weatherLabel(day.weatherCode)}  Sunrise ${DateFormat("h:mm a").format(day.sunrise)}",
      primary: "${_formatTemp(day.high)} / ${_formatTemp(day.low)}",
      trailing: "${day.precipitationProbability.round()}% rain  ${_formatSpeed(day.windSpeed)}",
    );
  }

  Widget _buildForecastRow({
    Key? key,
    required Color accent,
    required Color onSurface,
    required IconData icon,
    required String title,
    required String subtitle,
    required String primary,
    required String trailing,
    bool highlighted = false,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted ? accent.withAlpha(24) : onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: highlighted ? accent.withAlpha(85) : onSurface.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(135)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                primary,
                style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w800, color: onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                trailing,
                style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withAlpha(120)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 13, color: onSurface.withAlpha(170)),
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color onSurface) {
    return Text(
      label,
      style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: onSurface),
    );
  }

  Widget _buildMessageStrip(String message, Color color, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(190)),
      ),
    );
  }

  Widget _buildEmptyState({
    required Color accent,
    required Color onSurface,
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 28, color: accent),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: onSurface),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(145)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchLocations() async {
    final String query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _searchError = "Type at least two characters.";
        _searchResults = <_LocationSearchResult>[];
      });
      return;
    }

    final int token = ++_searchToken;
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResults = <_LocationSearchResult>[];
    });

    try {
      final Uri uri = Uri.https(
        "geocoding-api.open-meteo.com",
        "/v1/search",
        <String, String>{
          "name": query,
          "count": "8",
          "language": "en",
          "format": "json",
        },
      );
      final http.Response response = await http.get(uri);
      if (response.statusCode != 200) throw Exception("Search failed");

      final Map<String, dynamic> payload = jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> rawResults = payload["results"] as List<dynamic>? ?? <dynamic>[];
      final List<_LocationSearchResult> results = rawResults
          .whereType<Map<String, dynamic>>()
          .map(_LocationSearchResult.fromMap)
          .where((_LocationSearchResult result) => result.name.isNotEmpty)
          .toList();

      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchResults = results;
        _searchError = results.isEmpty ? "No matching locations found." : null;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchError = "Could not search locations right now.";
      });
    } finally {
      if (mounted && token == _searchToken) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _refreshForecasts({bool force = false}) async {
    final int token = ++_forecastToken;
    final List<_WeatherLocation> locations = List<_WeatherLocation>.from(_locations);

    for (final _WeatherLocation location in locations) {
      if (!force && _forecastCache.containsKey(location.id)) continue;
      if (!mounted || token != _forecastToken) return;

      setState(() {
        _loadingForecasts.add(location.id);
        _failedForecasts.remove(location.id);
      });

      try {
        final _WeatherForecast forecast = await _fetchForecast(location);
        if (!mounted || token != _forecastToken) return;
        setState(() {
          _forecastCache[location.id] = forecast;
        });
      } catch (_) {
        if (!mounted || token != _forecastToken) return;
        setState(() {
          _failedForecasts.add(location.id);
        });
      } finally {
        if (mounted && token == _forecastToken) {
          setState(() => _loadingForecasts.remove(location.id));
        }
      }
    }
  }

  Future<_WeatherForecast> _fetchForecast(_WeatherLocation location) async {
    final Uri uri = Uri.https(
      "api.open-meteo.com",
      "/v1/forecast",
      <String, String>{
        "latitude": location.latitude.toString(),
        "longitude": location.longitude.toString(),
        "current": "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m",
        "hourly":
            "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,weather_code,wind_speed_10m",
        "daily":
            "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,sunrise,sunset",
        "timezone": "auto",
        "forecast_days": "7",
        if (userSettings.weatherUnit == "u") "temperature_unit": "fahrenheit",
        if (userSettings.weatherUnit == "u") "wind_speed_unit": "mph",
      },
    );

    final http.Response response = await http.get(uri);
    if (response.statusCode != 200) throw Exception("Forecast failed");
    return _WeatherForecast.fromMap(jsonDecode(response.body) as Map<String, dynamic>);
  }

  void _scheduleCurrentHourCenter(_WeatherLocation location, _WeatherForecast forecast) {
    final WeatherHour? currentHour = _currentHour(forecast);
    if (currentHour == null) return;
    final int currentIndex = forecast.hourly.indexOf(currentHour);
    if (currentIndex < 0) return;

    final String hourId = "${location.id}:${_hourKey(currentHour.time)}";
    if (_lastCenteredHourId == hourId) return;
    _lastCenteredHourId = hourId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? rowContext = _currentHourKey.currentContext;
      if (!mounted || rowContext == null || !_detailScrollController.hasClients) return;

      final ScrollableState? scrollable = Scrollable.maybeOf(rowContext);
      final RenderBox? viewportBox = scrollable?.context.findRenderObject() as RenderBox?;
      final RenderBox? rowBox = rowContext.findRenderObject() as RenderBox?;
      if (viewportBox == null || rowBox == null) return;

      final ScrollPosition position = _detailScrollController.position;
      final double rowCenter = rowBox.localToGlobal(Offset(0, rowBox.size.height / 2)).dy;
      final double viewportCenter = viewportBox.localToGlobal(Offset(0, viewportBox.size.height / 2)).dy;
      final double targetOffset = (position.pixels + rowCenter - viewportCenter).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      unawaited(_detailScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ));
    });
  }

  WeatherHour? _currentHour(_WeatherForecast forecast) {
    final String currentKey = _hourKey(forecast.current.time);
    for (final WeatherHour hour in forecast.hourly) {
      if (_hourKey(hour.time) == currentKey) return hour;
    }
    return null;
  }

  bool _isCurrentHour(WeatherHour hour, _WeatherForecast forecast) {
    return _hourKey(hour.time) == _hourKey(forecast.current.time);
  }

  String _hourKey(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    return "${value.year}-$month-${day}T$hour";
  }

  void _addLocation(_LocationSearchResult result) {
    final _WeatherLocation location = result.toLocation();
    setState(() {
      _locations.add(location);
      _searchResults.remove(result);
      _searchError = null;
    });
    _saveLocations();
    unawaited(_refreshForecasts());
  }

  void _removeLocation(_WeatherLocation location) {
    setState(() {
      _locations.removeWhere((_WeatherLocation item) => item.id == location.id);
      _forecastCache.remove(location.id);
      _loadingForecasts.remove(location.id);
      _failedForecasts.remove(location.id);
    });
    _saveLocations();
  }

  void _moveLocation(int oldIndex, int newIndex) {
    if (newIndex < 0 || newIndex >= _locations.length) return;
    setState(() {
      final _WeatherLocation location = _locations.removeAt(oldIndex);
      _locations.insert(newIndex, location);
    });
    _saveLocations();
  }

  List<_WeatherLocation> _loadLocations() {
    final String? raw = Boxes.pref.getString(_locationsKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(_WeatherLocation.fromMap)
            .where((_WeatherLocation location) => location.isValid)
            .toList();
      } catch (_) {}
    }

    final List<String> legacyWeather = Boxes.pref.getStringList("weather") ?? userSettings.weather;
    if (legacyWeather.length > 1) {
      final List<String> parts = legacyWeather[1].split(',');
      if (parts.length >= 2) {
        final double? latitude = double.tryParse(parts[0].trim());
        final double? longitude = double.tryParse(parts[1].trim());
        if (latitude != null && longitude != null) {
          return <_WeatherLocation>[
            _WeatherLocation(
              name: "Saved Weather",
              subtitle: "Current weather setting",
              latitude: latitude,
              longitude: longitude,
            ),
          ];
        }
      }
    }

    return <_WeatherLocation>[];
  }

  Future<void> _saveLocations() async {
    await Boxes.updateSettings(
      _locationsKey,
      jsonEncode(_locations.map((_WeatherLocation location) => location.toMap()).toList()),
    );
  }

  String _formatTemp(double value) {
    return "${value.round()} ${userSettings.weatherUnit == "u" ? "F" : "C"}";
  }

  String _formatSpeed(double value) {
    return "${value.round()} ${userSettings.weatherUnit == "u" ? "mph" : "km/h"}";
  }

  IconData _weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code <= 3) return Icons.cloud_queue_rounded;
    if (code == 45 || code == 48) return Icons.foggy;
    if (code >= 51 && code <= 67) return Icons.grain_rounded;
    if (code >= 71 && code <= 86) return Icons.umbrella_outlined;
    if (code >= 95) return Icons.thunderstorm_rounded;
    return Icons.cloud_rounded;
  }

  String _weatherLabel(int code) {
    if (code == 0) return "Clear";
    if (code == 1) return "Mostly clear";
    if (code == 2) return "Partly cloudy";
    if (code == 3) return "Cloudy";
    if (code == 45 || code == 48) return "Fog";
    if (code >= 51 && code <= 57) return "Drizzle";
    if (code >= 61 && code <= 67) return "Rain";
    if (code >= 71 && code <= 77) return "Snow";
    if (code >= 80 && code <= 82) return "Showers";
    if (code >= 85 && code <= 86) return "Snow showers";
    if (code >= 95) return "Storm";
    return "Weather";
  }
}

enum _WeatherMode { overview, manage, detail }

enum _WeatherTab { today, daily }

class _WeatherLocation {
  const _WeatherLocation({
    required this.name,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  factory _WeatherLocation.fromMap(Map<String, dynamic> map) {
    return _WeatherLocation(
      name: (map["name"] ?? "").toString(),
      subtitle: (map["subtitle"] ?? "").toString(),
      latitude: ((map["latitude"] ?? 0) as num).toDouble(),
      longitude: ((map["longitude"] ?? 0) as num).toDouble(),
    );
  }

  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;

  String get id => "${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}";
  String get displayName => subtitle.isEmpty ? name : "$name, $subtitle";
  bool get isValid => name.trim().isNotEmpty && latitude.abs() <= 90 && longitude.abs() <= 180;

  bool matches(_LocationSearchResult result) {
    return (latitude - result.latitude).abs() < 0.001 && (longitude - result.longitude).abs() < 0.001;
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "name": name,
      "subtitle": subtitle,
      "latitude": latitude,
      "longitude": longitude,
    };
  }
}

class _LocationSearchResult {
  const _LocationSearchResult({
    required this.name,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  factory _LocationSearchResult.fromMap(Map<String, dynamic> map) {
    final List<String> subtitleParts = <String>[
      (map["admin1"] ?? "").toString(),
      (map["country"] ?? "").toString(),
    ].where((String value) => value.trim().isNotEmpty).toList();

    return _LocationSearchResult(
      name: (map["name"] ?? "").toString(),
      subtitle: subtitleParts.join(", "),
      latitude: ((map["latitude"] ?? 0) as num).toDouble(),
      longitude: ((map["longitude"] ?? 0) as num).toDouble(),
    );
  }

  final String name;
  final String subtitle;
  final double latitude;
  final double longitude;

  _WeatherLocation toLocation() {
    return _WeatherLocation(
      name: name,
      subtitle: subtitle,
      latitude: latitude,
      longitude: longitude,
    );
  }
}

class _WeatherForecast {
  const _WeatherForecast({
    required this.current,
    required this.hourly,
    required this.daily,
  });

  factory _WeatherForecast.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic> current = Map<String, dynamic>.from(map["current"] as Map<dynamic, dynamic>);
    final Map<String, dynamic> hourly = Map<String, dynamic>.from(map["hourly"] as Map<dynamic, dynamic>);
    final Map<String, dynamic> daily = Map<String, dynamic>.from(map["daily"] as Map<dynamic, dynamic>);
    final DateTime currentTime = DateTime.parse(current["time"].toString());
    final String todayKey = DateFormat("yyyy-MM-dd").format(currentTime);
    final DateTime earliestHour = DateTime(
      currentTime.year,
      currentTime.month,
      currentTime.day,
      currentTime.hour,
    ).subtract(const Duration(hours: 1));
    final List<dynamic> hourlyTimes = hourly["time"] as List<dynamic>? ?? <dynamic>[];
    final List<WeatherHour> hours = <WeatherHour>[];

    for (int index = 0; index < hourlyTimes.length; index++) {
      final DateTime time = DateTime.parse(hourlyTimes[index].toString());
      if (DateFormat("yyyy-MM-dd").format(time) != todayKey) continue;
      if (time.isBefore(earliestHour)) continue;
      hours.add(
        WeatherHour(
          time: time,
          temperature: _doubleAt(hourly, "temperature_2m", index),
          apparentTemperature: _doubleAt(hourly, "apparent_temperature", index),
          humidity: _doubleAt(hourly, "relative_humidity_2m", index),
          precipitationProbability: _doubleAt(hourly, "precipitation_probability", index),
          weatherCode: _intAt(hourly, "weather_code", index),
          windSpeed: _doubleAt(hourly, "wind_speed_10m", index),
        ),
      );
    }

    final List<dynamic> dailyTimes = daily["time"] as List<dynamic>? ?? <dynamic>[];
    final List<WeatherDay> days = <WeatherDay>[];
    for (int index = 0; index < dailyTimes.length; index++) {
      days.add(
        WeatherDay(
          date: DateTime.parse(dailyTimes[index].toString()),
          weatherCode: _intAt(daily, "weather_code", index),
          high: _doubleAt(daily, "temperature_2m_max", index),
          low: _doubleAt(daily, "temperature_2m_min", index),
          precipitationProbability: _doubleAt(daily, "precipitation_probability_max", index),
          windSpeed: _doubleAt(daily, "wind_speed_10m_max", index),
          sunrise: DateTime.parse(_stringAt(daily, "sunrise", index)),
          sunset: DateTime.parse(_stringAt(daily, "sunset", index)),
        ),
      );
    }

    return _WeatherForecast(
      current: _WeatherCondition(
        time: currentTime,
        temperature: ((current["temperature_2m"] ?? 0) as num).toDouble(),
        apparentTemperature: ((current["apparent_temperature"] ?? 0) as num).toDouble(),
        humidity: ((current["relative_humidity_2m"] ?? 0) as num).toDouble(),
        precipitation: ((current["precipitation"] ?? 0) as num).toDouble(),
        weatherCode: ((current["weather_code"] ?? 0) as num).toInt(),
        windSpeed: ((current["wind_speed_10m"] ?? 0) as num).toDouble(),
      ),
      hourly: hours,
      daily: days,
    );
  }

  final _WeatherCondition current;
  final List<WeatherHour> hourly;
  final List<WeatherDay> daily;
}

class _WeatherCondition {
  const _WeatherCondition({
    required this.time,
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.precipitation,
    required this.weatherCode,
    required this.windSpeed,
  });

  final DateTime time;
  final double temperature;
  final double apparentTemperature;
  final double humidity;
  final double precipitation;
  final int weatherCode;
  final double windSpeed;
}

class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.temperature,
    required this.apparentTemperature,
    required this.humidity,
    required this.precipitationProbability,
    required this.weatherCode,
    required this.windSpeed,
  });

  final DateTime time;
  final double temperature;
  final double apparentTemperature;
  final double humidity;
  final double precipitationProbability;
  final int weatherCode;
  final double windSpeed;
}

class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.weatherCode,
    required this.high,
    required this.low,
    required this.precipitationProbability,
    required this.windSpeed,
    required this.sunrise,
    required this.sunset,
  });

  final DateTime date;
  final int weatherCode;
  final double high;
  final double low;
  final double precipitationProbability;
  final double windSpeed;
  final DateTime sunrise;
  final DateTime sunset;
}

double _doubleAt(Map<String, dynamic> source, String key, int index) {
  final List<dynamic> values = source[key] as List<dynamic>? ?? <dynamic>[];
  if (index >= values.length) return 0;
  return ((values[index] ?? 0) as num).toDouble();
}

int _intAt(Map<String, dynamic> source, String key, int index) {
  final List<dynamic> values = source[key] as List<dynamic>? ?? <dynamic>[];
  if (index >= values.length) return 0;
  return ((values[index] ?? 0) as num).toInt();
}

String _stringAt(Map<String, dynamic> source, String key, int index) {
  final List<dynamic> values = source[key] as List<dynamic>? ?? <dynamic>[];
  if (index >= values.length) return DateTime.now().toIso8601String();
  return values[index].toString();
}
