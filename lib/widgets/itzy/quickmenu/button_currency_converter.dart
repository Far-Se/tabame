import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class CurrencyConverterButton extends StatelessWidget {
  const CurrencyConverterButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Currency Converter",
        icon: const Icon(Icons.currency_exchange_rounded),
        child: () => const CurrencyConverterWidget());
  }
}

class CurrencyConversionResult {
  const CurrencyConversionResult({
    required this.amount,
    required this.convertedAmount,
    required this.rate,
    required this.fromCurrency,
    required this.toCurrency,
    required this.fromName,
    required this.toName,
    required this.date,
  });

  final double amount;
  final double convertedAmount;
  final double rate;
  final String fromCurrency;
  final String toCurrency;
  final String fromName;
  final String toName;
  final String date;

  String get convertedLabel => '${CurrencyConverterService.formatNumber(convertedAmount)} ${toCurrency.toUpperCase()}';

  String get rateLabel =>
      '1 ${fromCurrency.toUpperCase()} = ${CurrencyConverterService.formatNumber(rate)} ${toCurrency.toUpperCase()}';
}

class CurrencyConverterService {
  static const String amountKey = "currencyConverterAmount";
  static const String fromKey = "currencyConverterFrom";
  static const String toKey = "currencyConverterTo";
  static const String _primaryBaseTemplate =
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{date}/v1/currencies";
  static const String _fallbackBaseTemplate = "https://{date}.currency-api.pages.dev/v1/currencies";

  static Map<String, String>? _currencyCatalogCache;

  Future<CurrencyConversionResult> convert(
    String rawInput, {
    String? defaultTargetCurrency,
  }) async {
    final Map<String, String> currencies = await _loadCurrencies();
    final Map<String, String> aliases = buildCurrencyAliases(currencies);
    final ParsedConversionInput parsed = parseConversionInput(
      rawInput,
      currencies: currencies,
      aliases: aliases,
      defaultTargetCurrency: defaultTargetCurrency,
    );

    if (parsed.query == null) {
      throw FormatException(parsed.message ?? "Use a format like 1 usd to eur.");
    }

    final ConversionQuery query = parsed.query!;
    final double rate =
        query.fromCurrency == query.toCurrency ? 1 : await _fetchRate(query.fromCurrency, query.toCurrency);
    final String fromName = currencies[query.fromCurrency] ?? query.fromCurrency.toUpperCase();
    final String toName = currencies[query.toCurrency] ?? query.toCurrency.toUpperCase();

    return CurrencyConversionResult(
      amount: query.amount,
      convertedAmount: query.amount * rate,
      rate: rate,
      fromCurrency: query.fromCurrency,
      toCurrency: query.toCurrency,
      fromName: fromName,
      toName: toName,
      date: DateTime.now().toIso8601String().split('T').first,
    );
  }

  static ParsedConversionInput parseConversionInput(
    String rawInput, {
    required Map<String, String> currencies,
    required Map<String, String> aliases,
    String? defaultTargetCurrency,
  }) {
    if (currencies.isEmpty) {
      return const ParsedConversionInput(message: "Loading currencies...");
    }

    String normalized = normalizeAlias(rawInput);
    if (normalized.isEmpty) {
      return const ParsedConversionInput(
        message: "Type something like 1 usd to ron.",
      );
    }

    final String? defaultTarget =
        defaultTargetCurrency == null ? null : resolveCurrencyAlias(defaultTargetCurrency, aliases: aliases);
    if (defaultTarget != null && !RegExp(r'\s+(?:to|in|into|=|->)\s+').hasMatch(normalized)) {
      normalized = '$normalized to $defaultTarget';
    }

    final RegExpMatch? amountMatch = RegExp(
      r'^(?:(\d+(?:[.,]\d+)?)\s+)?(.+)$',
    ).firstMatch(normalized);
    if (amountMatch == null) {
      return const ParsedConversionInput(
        message: "Use a format like 1 usd to ron.",
      );
    }

    final double amount = double.tryParse((amountMatch.group(1) ?? "1").replaceAll(',', '.')) ?? 1;
    final String remainder = (amountMatch.group(2) ?? "").trim();
    final List<String> parts = remainder.split(RegExp(r'\s+(?:to|in|into|=|->)\s+'));

    if (parts.length != 2) {
      return const ParsedConversionInput(
        message: "Use a format like 1 usd to ron.",
      );
    }

    final String? fromCode = resolveCurrencyAlias(parts[0], aliases: aliases);
    if (fromCode == null) {
      return ParsedConversionInput(
        message: "I couldn't recognize `${parts[0].trim()}`.",
      );
    }

    final String? toCode = resolveCurrencyAlias(parts[1], aliases: aliases);
    if (toCode == null) {
      return ParsedConversionInput(
        message: "I couldn't recognize `${parts[1].trim()}`.",
      );
    }

    final String fromName = currencies[fromCode] ?? fromCode.toUpperCase();
    final String toName = currencies[toCode] ?? toCode.toUpperCase();

    return ParsedConversionInput(
      query: ConversionQuery(
        amount: amount,
        fromCurrency: fromCode,
        toCurrency: toCode,
      ),
      message: "${fromCode.toUpperCase()} ($fromName) to ${toCode.toUpperCase()} ($toName)",
    );
  }

  static String? resolveCurrencyAlias(
    String rawAlias, {
    required Map<String, String> aliases,
  }) {
    final String normalized = normalizeAlias(rawAlias);
    if (normalized.isEmpty) return null;
    return aliases[normalized];
  }

  static Map<String, String> buildCurrencyAliases(Map<String, String> currencies) {
    final Map<String, String> aliases = <String, String>{};

    void register(String alias, String code) {
      final String normalized = normalizeAlias(alias);
      if (normalized.isEmpty) return;
      aliases.putIfAbsent(normalized, () => code);
    }

    currencies.forEach((String code, String name) {
      register(code, code);
      register(name, code);
    });

    const Map<String, List<String>> manualAliases = <String, List<String>>{
      "usd": <String>[
        "us dollar",
        "us dollars",
        "american dollar",
        "american dollars",
      ],
      "eur": <String>["euro", "euros"],
      "gbp": <String>["british pound", "british pounds", "quid"],
      "ron": <String>["leu", "lei", "romanian leu", "romanian lei"],
      "jpy": <String>["yen", "japanese yen"],
      "cny": <String>["yuan", "renminbi", "chinese yuan"],
      "inr": <String>["rupee", "rupees", "indian rupee", "indian rupees"],
      "try": <String>["turkish lira"],
      "cad": <String>["canadian dollar", "canadian dollars"],
      "aud": <String>["australian dollar", "australian dollars"],
      "brl": <String>["brazilian real", "brazilian reais"],
      "aed": <String>["uae dirham", "emirati dirham"],
      "mxn": <String>["mexican peso", "mexican pesos"],
      "rub": <String>["ruble", "rubles", "rouble", "roubles"],
    };

    manualAliases.forEach((String code, List<String> values) {
      if (!currencies.containsKey(code)) return;
      for (final String alias in values) {
        register(alias, code);
      }
    });

    return aliases;
  }

  static String normalizeAlias(String value) {
    final String normalized = value
        .toLowerCase()
        .replaceAll('\u0103', 'a')
        .replaceAll('\u00e2', 'a')
        .replaceAll('\u00ee', 'i')
        .replaceAll('\u0219', 's')
        .replaceAll('\u015f', 's')
        .replaceAll('\u021b', 't')
        .replaceAll('\u0163', 't')
        .replaceAll('Äƒ', 'a')
        .replaceAll('Ã¢', 'a')
        .replaceAll('Ã®', 'i')
        .replaceAll('È™', 's')
        .replaceAll('ÅŸ', 's')
        .replaceAll('È›', 't')
        .replaceAll('Å£', 't');

    return normalized.replaceAll(RegExp(r'[^a-z0-9\s.,-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String formatNumber(double value) {
    if (value.abs() >= 1000) return value.formatNum2();
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  Future<Map<String, String>> _loadCurrencies() async {
    if (_currencyCatalogCache != null) return _currencyCatalogCache!;

    final Map<String, dynamic> jsonMap = await fetchJsonWithFallback(
      catalogUrl(),
      catalogUrl(fallback: true),
    );
    _currencyCatalogCache = jsonMap.map(
      (String key, dynamic value) => MapEntry<String, String>(key.toLowerCase(), (value ?? '').toString()),
    );
    return _currencyCatalogCache!;
  }

  Future<double> _fetchRate(String fromCurrency, String toCurrency) async {
    final String base = fromCurrency.toLowerCase();
    final String target = toCurrency.toLowerCase();
    final Map<String, dynamic> jsonMap = await fetchJsonWithFallback(
      baseRatesUrl(base),
      baseRatesUrl(base, fallback: true),
    );
    final Map<String, dynamic> baseMap = Map<String, dynamic>.from(
      (jsonMap[base] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
    final dynamic value = baseMap[target];
    if (value is num) return value.toDouble();
    throw Exception("Could not fetch live exchange rates.");
  }

  static Future<Map<String, dynamic>> fetchJsonWithFallback(String primaryUrl, String fallbackUrl) async {
    final http.Response primary = await http.get(Uri.parse(primaryUrl));
    if (primary.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(primary.body) as Map<String, dynamic>);
    }

    final http.Response fallback = await http.get(Uri.parse(fallbackUrl));
    if (fallback.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(fallback.body) as Map<String, dynamic>);
    }

    throw Exception("Request failed");
  }

  static String catalogUrl({bool fallback = false}) {
    final String base = fallback
        ? _fallbackBaseTemplate.replaceFirst("{date}", "latest")
        : _primaryBaseTemplate.replaceFirst("{date}", "latest");
    return "$base.min.json";
  }

  static String baseRatesUrl(
    String baseCurrency, {
    String date = "latest",
    bool fallback = false,
  }) {
    final String base = fallback
        ? _fallbackBaseTemplate.replaceFirst("{date}", date)
        : _primaryBaseTemplate.replaceFirst("{date}", date);
    return "$base/${baseCurrency.toLowerCase()}.min.json";
  }
}

class CurrencyConverterWidget extends StatefulWidget {
  const CurrencyConverterWidget({super.key});

  @override
  State<CurrencyConverterWidget> createState() => _CurrencyConverterWidgetState();
}

class _CurrencyConverterWidgetState extends State<CurrencyConverterWidget> {
  static const String _amountKey = "currencyConverterAmount";
  static const String _fromKey = "currencyConverterFrom";
  static const String _toKey = "currencyConverterTo";
  static const int _historyWindowDays = 30;
  static const String _historyFileName = "currency_history.json";
  static const String _primaryBaseTemplate =
      "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@{date}/v1/currencies";
  static const String _fallbackBaseTemplate = "https://{date}.currency-api.pages.dev/v1/currencies";

  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final VoidCallback _amountListener;
  int _ratesRequestToken = 0;
  int _historyRequestToken = 0;

  Map<String, String>? _currencyCatalogCache;
  Map<String, dynamic> _historyCache = <String, dynamic>{};
  Map<String, String> _currencyAliases = <String, String>{};
  final Map<String, _RatesResponse> _ratesCache = <String, _RatesResponse>{};
  Map<String, String> _currencies = <String, String>{};
  Map<String, double> _rates = <String, double>{};
  List<_HistoryPoint> _historyPoints = <_HistoryPoint>[];
  bool _loadingCatalog = true;
  bool _loadingRates = false;
  bool _loadingHistory = false;
  bool _historyCacheLoaded = false;
  String? _errorMessage;
  String? _inputMessage;
  String? _historyError;
  String _fromCurrency = "usd";
  String _toCurrency = "eur";
  String? _ratesDate;
  String? _historyPairKey;

  @override
  void initState() {
    super.initState();
    final String savedFrom = (Boxes.pref.getString(_fromKey) ?? "usd").toLowerCase();
    final String savedTo = (Boxes.pref.getString(_toKey) ?? "eur").toLowerCase();
    final String savedQuery = (Boxes.pref.getString(_amountKey) ?? "").trim();
    _fromCurrency = savedFrom;
    _toCurrency = savedTo;
    _amountController.text =
        savedQuery.isEmpty ? "1 ${savedFrom.toUpperCase()} to ${savedTo.toUpperCase()}" : savedQuery;
    _amountController.selection = const TextSelection.collapsed(offset: 0);
    _amountListener = () {
      Boxes.updateSettings(_amountKey, _amountController.text.trim());
      unawaited(_handleQueryChanged());
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _amountFocus.requestFocus();
      _amountController.selection = const TextSelection.collapsed(offset: 0);
    });
    _amountController.addListener(_amountListener);
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _amountController.removeListener(_amountListener);
    _amountController.dispose();
    _scrollController.dispose();
    _currencies.clear();
    _rates.clear();
    _historyPoints.clear();
    _currencyAliases.clear();
    _currencyCatalogCache = null;
    _historyCache = <String, dynamic>{};
    _ratesCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;
    final double amount = _parsedAmount;
    final double? rate = _currentRate;
    final double convertedAmount = amount * (rate ?? 0);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface.withAlpha(220),
          border: Border.all(color: onSurface.withAlpha(22), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PanelHeader(
              title: "Currency Converter",
              icon: Icons.currency_exchange_rounded,
              buttonPressed: _refreshRates,
              buttonIcon: Icons.refresh_rounded,
            ),
            if (_loadingCatalog || _loadingRates) const LinearProgressIndicator(minHeight: 1.5),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildAmountField(accent, onSurface),
                    const SizedBox(height: 12),
                    _buildResultCard(
                      accent: accent,
                      onSurface: onSurface,
                      amount: amount,
                      convertedAmount: convertedAmount,
                      rate: rate,
                    ),
                    const SizedBox(height: 12),
                    _buildHistorySection(accent, onSurface),
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 2,
                          color: Colors.redAccent.withAlpha(210),
                        ),
                      ),
                    ],
                    if (_inputMessage != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          _inputMessage!,
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 2,
                            color: onSurface.withAlpha(170),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _buildInfoChip("Base: ${_fromCurrency.toUpperCase()}"),
                        if (_ratesDate != null) _buildInfoChip("Updated $_ratesDate"),
                        _buildInfoChip("@fawazahmed0/currency-api"),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _flipCurrencies() {
    final String text = _amountController.text.trim();
    final ParsedConversionInput parsed = _parseConversionInput(text);

    // If the current query is valid, flip it gracefully
    if (parsed.query != null) {
      final double amount = parsed.query!.amount;
      final String from = parsed.query!.fromCurrency.toUpperCase();
      final String to = parsed.query!.toCurrency.toUpperCase();

      // Format the amount neatly using the existing helper method
      // final String formattedAmount = amount;

      _amountController.text = "$amount $to to $from";
    } else {
      // Fallback if input is messy or blank: flip the last known state variables
      final String from = _fromCurrency.toUpperCase();
      final String to = _toCurrency.toUpperCase();
      _amountController.text = "1 $to to $from";
    }

    // Move selection cursor to the end of the input field
    _amountController.selection = const TextSelection.collapsed(offset: 0);
    _amountFocus.requestFocus();
  }

  Widget _buildAmountField(Color accent, Color onSurface) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              "Amount",
              style: TextStyle(
                fontSize: Design.baseFontSize + 2,
                fontWeight: FontWeight.w600,
                color: onSurface.withAlpha(185),
              ),
            ),
            const Spacer(),
            // Flip Currency Button
            IconButton(
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 16,
              color: accent,
              tooltip: "Flip Currencies",
              onPressed: _flipCurrencies,
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _amountController,
          focusNode: _amountFocus,
          keyboardType: TextInputType.text,
          autofocus: true,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: "1 usd to eur",
            prefixIcon: Icon(Icons.payments_outlined, size: 16, color: accent),
            filled: true,
            fillColor: accent.withAlpha(12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
      ],
    );
  }

  Widget _buildResultCard({
    required Color accent,
    required Color onSurface,
    required double amount,
    required double convertedAmount,
    required double? rate,
  }) {
    // Calculate the reverse exchange rate safely
    final double? reverseRate = (rate != null && rate != 0) ? 1.0 / rate : null;

    return Container(
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: rate == null ? null : () => _copyToClipboard(_formatNumber(convertedAmount)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      rate == null ? " " : "${_formatNumber(convertedAmount)} ${_toCurrency.toUpperCase()}",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Forward Rate (e.g., 1 EUR = X USD)
                  Center(
                    child: Text(
                      rate == null
                          ? " "
                          : "1 ${_fromCurrency.toUpperCase()} = ${_formatNumber(rate)} ${_toCurrency.toUpperCase()}",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2,
                        color: onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  // Reverse Rate (e.g., 1 USD = Y EUR)
                  if (rate != null && reverseRate != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        "1 ${_toCurrency.toUpperCase()} = ${_formatNumber(reverseRate)} ${_fromCurrency.toUpperCase()}",
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 2,
                          color: onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  Icons.content_copy_rounded,
                  size: 14,
                  color: rate == null ? onSurface.withAlpha(70) : onSurface.withAlpha(130),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistorySection(Color accent, Color onSurface) {
    final ParsedConversionInput parsed = _parseConversionInput(_amountController.text);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.show_chart_rounded, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(
                "Last 30 Days",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
              const Spacer(),
              Text(
                "${_fromCurrency.toUpperCase()} -> ${_toCurrency.toUpperCase()}",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  color: onSurface.withAlpha(145),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (parsed.query == null)
            _buildHistoryMessage(
              onSurface,
              "Enter a valid currency pair to load history.",
            )
          else if (_loadingHistory)
            _buildHistorySkeleton(onSurface)
          else if (_historyPoints.isNotEmpty)
            _buildHistoryChart(accent, onSurface)
          else
            _buildHistoryMessage(
              onSurface,
              _historyError ?? "No history available for this pair yet.",
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryChart(Color accent, Color onSurface) {
    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < _historyPoints.length; i++) FlSpot(i.toDouble(), _historyPoints[i].value),
    ];
    final List<double> values = _historyPoints.map((_HistoryPoint a) => a.value).toList(growable: false);
    final double minValue = values.reduce(math.min);
    final double maxValue = values.reduce(math.max);
    final double verticalPadding =
        (maxValue - minValue).abs() < 0.001 ? math.max(0.05, maxValue.abs() * 0.02) : (maxValue - minValue) * 0.18;

    return SizedBox(
      height: 170,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (_historyPoints.length - 1).toDouble(),
          minY: minValue - verticalPadding,
          maxY: maxValue + verticalPadding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (double value) {
              return FlLine(
                color: onSurface.withAlpha(18),
                strokeWidth: 1,
              );
            },
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (double value, TitleMeta meta) {
                  return Text(
                    _formatNumber(value),
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      color: onSurface.withAlpha(120),
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int index = value.round();
                  if (index < 0 || index >= _historyPoints.length) {
                    return const SizedBox.shrink();
                  }

                  final bool showLabel =
                      index == 0 || index == _historyPoints.length ~/ 2 || index == _historyPoints.length - 1;
                  if (!showLabel) {
                    return const SizedBox.shrink();
                  }

                  return SideTitleWidget(
                    meta: meta,
                    space: 8,
                    child: Text(
                      _formatChartLabel(_historyPoints[index].date),
                      style: TextStyle(
                        fontSize: Design.baseFontSize,
                        color: onSurface.withAlpha(120),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBorderRadius: const BorderRadius.all(Radius.elliptical(10, 10)),
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((LineBarSpot spot) {
                  final int index = spot.x.round();
                  if (index < 0 || index >= _historyPoints.length) {
                    return null;
                  }

                  final _HistoryPoint point = _historyPoints[index];
                  return LineTooltipItem(
                    "${_formatApiDate(point.date)}\n${_formatNumber(point.value)} ${_toCurrency.toUpperCase()}",
                    TextStyle(
                      color: onSurface,
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: accent,
              barWidth: 2.5,
              isStrokeCapRound: true,
              belowBarData: BarAreaData(
                show: true,
                color: accent.withAlpha(26),
              ),
              dotData: FlDotData(show: _historyPoints.length < 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySkeleton(Color onSurface) {
    return SizedBox(
      height: 170,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _buildSkeletonBlock(width: 52, height: 10, color: onSurface),
              const Spacer(),
              _buildSkeletonBlock(width: 58, height: 10, color: onSurface),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(12, (int index) {
                final List<double> heights = <double>[
                  44,
                  68,
                  52,
                  80,
                  74,
                  95,
                  88,
                  102,
                  90,
                  112,
                  98,
                  120,
                ];
                return Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _buildSkeletonBlock(
                        width: double.infinity,
                        height: heights[index],
                        color: onSurface,
                        radius: 999,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _buildSkeletonBlock(width: 34, height: 10, color: onSurface),
              _buildSkeletonBlock(width: 34, height: 10, color: onSurface),
              _buildSkeletonBlock(width: 34, height: 10, color: onSurface),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonBlock({
    required double width,
    required double height,
    required Color color,
    double radius = 6,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildHistoryMessage(Color onSurface, String message) {
    return SizedBox(
      height: 170,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: Design.baseFontSize + 2,
            color: onSurface.withAlpha(145),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: userSettings.themeColors.accent.withAlpha(12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Design.baseFontSize + 1,
          color: Theme.of(context).colorScheme.onSurface.withAlpha(165),
        ),
      ),
    );
  }

  double get _parsedAmount {
    final ParsedConversionInput parsed = _parseConversionInput(_amountController.text);
    return parsed.query?.amount ?? 1;
  }

  double? get _currentRate {
    if (_fromCurrency == _toCurrency) return 1;
    return _rates[_toCurrency];
  }

  String get _historyCachePath => "${WinUtils.getTabameAppDataFolder(settings: true)}\\$_historyFileName";

  Future<void> _initialize() async {
    await _loadHistoryCacheFile();
    await _loadCurrencies();
    await _handleQueryChanged();
  }

  Future<void> _refreshRates() async {
    _ratesCache.remove(_fromCurrency);
    await _loadCurrencies(forceRefresh: true);
    await _loadRatesForBase(_fromCurrency, forceRefresh: true);
    unawaited(
      _loadHistoryForPair(_fromCurrency, _toCurrency, forceRefresh: true),
    );
  }

  Future<void> _loadCurrencies({bool forceRefresh = false}) async {
    setState(() {
      _loadingCatalog = true;
      _errorMessage = null;
    });

    try {
      if (!forceRefresh && _currencyCatalogCache != null) {
        _currencies = _currencyCatalogCache!;
      } else {
        final Map<String, dynamic> jsonMap = await _fetchJsonWithFallback(
          _catalogUrl(),
          _catalogUrl(fallback: true),
        );
        _currencies = jsonMap.map(
          (String key, dynamic value) => MapEntry<String, String>(key.toLowerCase(), (value ?? '').toString()),
        );
        _currencyCatalogCache = Map<String, String>.from(_currencies);
      }

      _currencyAliases = _buildCurrencyAliases(_currencies);

      if (!_currencies.containsKey(_fromCurrency)) {
        _fromCurrency = "usd";
      }
      if (!_currencies.containsKey(_toCurrency)) {
        _toCurrency = "eur";
      }
    } catch (_) {
      _errorMessage = "Unable to load currencies right now.";
    } finally {
      if (mounted) {
        setState(() {
          _loadingCatalog = false;
        });
      }
    }
  }

  Future<void> _loadRatesForBase(String baseCurrency, {bool forceRefresh = false}) async {
    final String base = baseCurrency.toLowerCase();
    final int requestToken = ++_ratesRequestToken;
    setState(() {
      _loadingRates = true;
      _errorMessage = null;
    });

    try {
      if (!forceRefresh && _ratesCache.containsKey(base)) {
        final _RatesResponse cached = _ratesCache[base]!;
        if (!mounted || requestToken != _ratesRequestToken) return;
        _rates = cached.rates;
        _ratesDate = cached.date;
      } else {
        final Map<String, dynamic> jsonMap = await _fetchJsonWithFallback(
          _baseRatesUrl(base),
          _baseRatesUrl(base, fallback: true),
        );

        final Map<String, dynamic> baseMap = Map<String, dynamic>.from(
          (jsonMap[base] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        final Map<String, double> rates = baseMap.map(
          (String key, dynamic value) => MapEntry<String, double>(key.toLowerCase(), (value as num).toDouble()),
        );

        final _RatesResponse response = _RatesResponse(
          date: (jsonMap["date"] ?? "").toString(),
          rates: rates,
        );
        _ratesCache[base] = response;
        if (!mounted || requestToken != _ratesRequestToken) return;
        _rates = response.rates;
        _ratesDate = response.date;
      }

      await Boxes.updateSettings(_fromKey, _fromCurrency);
      await Boxes.updateSettings(_toKey, _toCurrency);
    } catch (_) {
      if (!mounted || requestToken != _ratesRequestToken) return;
      _errorMessage = "Could not fetch live exchange rates.";
      _rates = <String, double>{};
      _ratesDate = null;
    } finally {
      if (mounted && requestToken == _ratesRequestToken) {
        setState(() {
          _loadingRates = false;
        });
      }
    }
  }

  Future<void> _loadHistoryCacheFile() async {
    if (_historyCacheLoaded) return;

    try {
      final File file = File(_historyCachePath);
      if (file.existsSync()) {
        final String raw = file.readAsStringSync();
        if (raw.trim().isNotEmpty) {
          final Object? decoded = jsonDecode(raw);
          if (decoded is Map) {
            _historyCache = decoded.map(
              (dynamic key, dynamic value) => MapEntry<String, dynamic>(key.toString(), value),
            );
          }
        }
      }
    } catch (_) {
      _historyCache = <String, dynamic>{};
    } finally {
      _historyCacheLoaded = true;
    }
  }

  Future<void> _writeHistoryCacheFile() async {
    final File file = File(_historyCachePath);
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    file.writeAsStringSync(jsonEncode(_historyCache));
  }

  Future<void> _loadHistoryForPair(
    String fromCurrency,
    String toCurrency, {
    bool forceRefresh = false,
  }) async {
    if (!_historyCacheLoaded) {
      await _loadHistoryCacheFile();
    }

    final String pairKey = _pairKey(fromCurrency, toCurrency);
    final int requestToken = ++_historyRequestToken;
    final List<String> last30Dates = _last30DateKeys();
    final Set<String> last30DateSet = last30Dates.toSet();

    setState(() {
      _loadingHistory = true;
      _historyError = null;
      _historyPairKey = pairKey;
      _historyPoints = <_HistoryPoint>[];
    });

    try {
      Map<String, double> values = forceRefresh ? <String, double>{} : _historyValuesFromCache(pairKey)
        ..removeWhere(
          (String date, double value) => !last30DateSet.contains(date),
        );

      if (fromCurrency == toCurrency) {
        values = <String, double>{
          for (final String date in last30Dates) date: 1,
        };
      } else {
        final List<String> missingDates = last30Dates.where((String date) => !values.containsKey(date)).toList();

        for (final String date in missingDates) {
          if (!mounted || requestToken != _historyRequestToken) return;
          final double? rate = await _fetchHistoricalRate(
            fromCurrency,
            toCurrency,
            date,
          );
          if (rate != null) {
            values[date] = rate;
          }
        }
      }

      if (!mounted || requestToken != _historyRequestToken) return;

      final Map<String, double> trimmedValues = <String, double>{
        for (final String date in last30Dates)
          if (values.containsKey(date)) date: values[date]!,
      };

      _historyCache[pairKey] = <String, dynamic>{
        "base": fromCurrency,
        "target": toCurrency,
        "values": trimmedValues.map(
          (String key, double value) => MapEntry<String, dynamic>(key, value),
        ),
      };
      await _writeHistoryCacheFile();

      final List<_HistoryPoint> points = trimmedValues.entries
          .map(
            (MapEntry<String, double> entry) => _HistoryPoint(
              date: DateTime.parse(entry.key),
              value: entry.value,
            ),
          )
          .toList()
        ..sort((_HistoryPoint a, _HistoryPoint b) => a.date.compareTo(b.date));

      if (!mounted || requestToken != _historyRequestToken) return;

      setState(() {
        _historyPoints = points;
        _historyError = points.isEmpty ? "No recent history could be loaded for this pair." : null;
      });
    } catch (_) {
      if (!mounted || requestToken != _historyRequestToken) return;
      setState(() {
        _historyError = "Could not load the last 30 days of history.";
        _historyPoints = <_HistoryPoint>[];
      });
    } finally {
      if (mounted && requestToken == _historyRequestToken) {
        setState(() {
          _loadingHistory = false;
        });
      }
    }
  }

  Map<String, double> _historyValuesFromCache(String pairKey) {
    final Map<String, dynamic> pairEntry = Map<String, dynamic>.from(
      (_historyCache[pairKey] as Map<dynamic, dynamic>?) ?? <String, dynamic>{},
    );
    final Map<String, dynamic> rawValues = Map<String, dynamic>.from(
      (pairEntry["values"] as Map<dynamic, dynamic>?) ?? <String, dynamic>{},
    );
    return rawValues.map(
      (String key, dynamic value) => MapEntry<String, double>(
        key,
        (value as num).toDouble(),
      ),
    );
  }

  Future<double?> _fetchHistoricalRate(
    String fromCurrency,
    String toCurrency,
    String date,
  ) async {
    try {
      final Map<String, dynamic> jsonMap = await _fetchJsonWithFallback(
        _baseRatesUrl(fromCurrency, date: date),
        _baseRatesUrl(fromCurrency, date: date, fallback: true),
      );
      final Map<String, dynamic> baseMap = Map<String, dynamic>.from(
        (jsonMap[fromCurrency] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );
      final dynamic value = baseMap[toCurrency];
      if (value is num) {
        return value.toDouble();
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _fetchJsonWithFallback(String primaryUrl, String fallbackUrl) async {
    final http.Response primary = await http.get(Uri.parse(primaryUrl));
    if (primary.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(primary.body) as Map<String, dynamic>);
    }

    final http.Response fallback = await http.get(Uri.parse(fallbackUrl));
    if (fallback.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(fallback.body) as Map<String, dynamic>);
    }

    throw Exception("Request failed");
  }

  String _formatNumber(double value) {
    if (value.abs() >= 1000) return value.formatNum2();
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  void _copyToClipboard(String value) {
    Clipboard.setData(ClipboardData(text: value));
  }

  Future<void> _handleQueryChanged() async {
    final ParsedConversionInput parsed = _parseConversionInput(_amountController.text);
    final String previousBase = _fromCurrency;

    if (!mounted) return;

    setState(() {
      _inputMessage = parsed.message;
      if (parsed.query != null) {
        _fromCurrency = parsed.query!.fromCurrency;
        _toCurrency = parsed.query!.toCurrency;
      } else {
        _ratesDate = null;
        _historyPairKey = null;
        _historyError = null;
        _historyPoints = <_HistoryPoint>[];
      }
    });

    if (parsed.query == null) {
      _rates = <String, double>{};
      return;
    }

    await Boxes.updateSettings(_fromKey, _fromCurrency);
    await Boxes.updateSettings(_toKey, _toCurrency);

    if (previousBase != _fromCurrency || _rates.isEmpty) {
      await _loadRatesForBase(_fromCurrency);
    }

    final String pairKey = _pairKey(_fromCurrency, _toCurrency);
    if (_historyPairKey != pairKey || _historyPoints.isEmpty) {
      unawaited(_loadHistoryForPair(_fromCurrency, _toCurrency));
    }
  }

  ParsedConversionInput _parseConversionInput(String rawInput) {
    if (_currencies.isEmpty) {
      return const ParsedConversionInput(message: "Loading currencies...");
    }

    final String normalized = _normalizeAlias(rawInput);
    if (normalized.isEmpty) {
      return const ParsedConversionInput(
        message: "Type something like 1 usd to ron.",
      );
    }

    final RegExpMatch? amountMatch = RegExp(
      r'^(?:(\d+(?:[.,]\d+)?)\s+)?(.+)$',
    ).firstMatch(normalized);
    if (amountMatch == null) {
      return const ParsedConversionInput(
        message: "Use a format like 1 usd to ron.",
      );
    }

    final double amount = double.tryParse((amountMatch.group(1) ?? "1").replaceAll(',', '.')) ?? 1;
    final String remainder = (amountMatch.group(2) ?? "").trim();
    final List<String> parts = remainder.split(RegExp(r'\s+(?:to|in|into|=|->)\s+'));

    if (parts.length != 2) {
      return const ParsedConversionInput(
        message: "Use a format like 1 usd to ron.",
      );
    }

    final String? fromCode = _resolveCurrencyAlias(parts[0]);
    if (fromCode == null) {
      return ParsedConversionInput(
        message: "I couldn't recognize `${parts[0].trim()}`.",
      );
    }

    final String? toCode = _resolveCurrencyAlias(parts[1]);
    if (toCode == null) {
      return ParsedConversionInput(
        message: "I couldn't recognize `${parts[1].trim()}`.",
      );
    }

    final String fromName = _currencies[fromCode] ?? fromCode.toUpperCase();
    final String toName = _currencies[toCode] ?? toCode.toUpperCase();

    return ParsedConversionInput(
      query: ConversionQuery(
        amount: amount,
        fromCurrency: fromCode,
        toCurrency: toCode,
      ),
      message: "${fromCode.toUpperCase()} ($fromName) to ${toCode.toUpperCase()} ($toName)",
    );
  }

  String? _resolveCurrencyAlias(String rawAlias) {
    final String normalized = _normalizeAlias(rawAlias);
    if (normalized.isEmpty) return null;
    return _currencyAliases[normalized];
  }

  Map<String, String> _buildCurrencyAliases(Map<String, String> currencies) {
    final Map<String, String> aliases = <String, String>{};

    void register(String alias, String code) {
      final String normalized = _normalizeAlias(alias);
      if (normalized.isEmpty) return;
      aliases.putIfAbsent(normalized, () => code);
    }

    currencies.forEach((String code, String name) {
      register(code, code);
      register(name, code);
    });

    const Map<String, List<String>> manualAliases = <String, List<String>>{
      "usd": <String>[
        "us dollar",
        "us dollars",
        "american dollar",
        "american dollars",
      ],
      "eur": <String>["euro", "euros"],
      "gbp": <String>["british pound", "british pounds", "quid"],
      "ron": <String>["leu", "lei", "romanian leu", "romanian lei"],
      "jpy": <String>["yen", "japanese yen"],
      "cny": <String>["yuan", "renminbi", "chinese yuan"],
      "inr": <String>["rupee", "rupees", "indian rupee", "indian rupees"],
      "try": <String>["turkish lira"],
      "cad": <String>["canadian dollar", "canadian dollars"],
      "aud": <String>["australian dollar", "australian dollars"],
      "brl": <String>["brazilian real", "brazilian reais"],
      "aed": <String>["uae dirham", "emirati dirham"],
      "mxn": <String>["mexican peso", "mexican pesos"],
      "rub": <String>["ruble", "rubles", "rouble", "roubles"],
    };

    manualAliases.forEach((String code, List<String> values) {
      if (!currencies.containsKey(code)) return;
      for (final String alias in values) {
        register(alias, code);
      }
    });

    return aliases;
  }

  String _normalizeAlias(String value) {
    final String normalized = value
        .toLowerCase()
        .replaceAll('\u0103', 'a')
        .replaceAll('\u00e2', 'a')
        .replaceAll('\u00ee', 'i')
        .replaceAll('\u0219', 's')
        .replaceAll('\u015f', 's')
        .replaceAll('\u021b', 't')
        .replaceAll('\u0163', 't')
        .replaceAll('ă', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ș', 's')
        .replaceAll('ş', 's')
        .replaceAll('ț', 't')
        .replaceAll('ţ', 't');

    return normalized.replaceAll(RegExp(r'[^a-z0-9\s.,-]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _catalogUrl({bool fallback = false}) {
    final String base = fallback
        ? _fallbackBaseTemplate.replaceFirst("{date}", "latest")
        : _primaryBaseTemplate.replaceFirst("{date}", "latest");
    return "$base.min.json";
  }

  String _baseRatesUrl(
    String baseCurrency, {
    String date = "latest",
    bool fallback = false,
  }) {
    final String base = fallback
        ? _fallbackBaseTemplate.replaceFirst("{date}", date)
        : _primaryBaseTemplate.replaceFirst("{date}", date);
    return "$base/${baseCurrency.toLowerCase()}.min.json";
  }

  List<String> _last30DateKeys() {
    final DateTime now = DateTime.now();
    final DateTime end = DateTime(now.year, now.month, now.day);
    return List<String>.generate(_historyWindowDays, (int index) {
      final int offset = _historyWindowDays - index - 1;
      return _formatApiDate(end.subtract(Duration(days: offset)));
    });
  }

  String _pairKey(String fromCurrency, String toCurrency) {
    return "${fromCurrency.toLowerCase()}_${toCurrency.toLowerCase()}";
  }

  String _formatApiDate(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return "$year-$month-$day";
  }

  String _formatChartLabel(DateTime date) {
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');
    return "$day/$month";
  }
}

class _RatesResponse {
  const _RatesResponse({
    required this.date,
    required this.rates,
  });

  final String date;
  final Map<String, double> rates;
}

class ConversionQuery {
  const ConversionQuery({
    required this.amount,
    required this.fromCurrency,
    required this.toCurrency,
  });

  final double amount;
  final String fromCurrency;
  final String toCurrency;
}

class ParsedConversionInput {
  const ParsedConversionInput({
    this.query,
    this.message,
  });

  final ConversionQuery? query;
  final String? message;
}

class _HistoryPoint {
  const _HistoryPoint({
    required this.date,
    required this.value,
  });

  final DateTime date;
  final double value;
}
