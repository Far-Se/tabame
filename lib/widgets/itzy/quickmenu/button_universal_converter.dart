import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class UniversalConverterButton extends StatelessWidget {
  const UniversalConverterButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Unit Converter",
      icon: const Icon(Icons.straighten_rounded),
      child: () => const UniversalConverterWidget(),
    );
  }
}

/// A single unit: which category it belongs to and its factor relative to the
/// category's base unit. Temperature units carry a factor of 1 and are handled
/// with explicit affine formulas instead.
class _Unit {
  const _Unit(this.category, this.factor);
  final String category;
  final double factor;
}

/// A canonical (deduplicated) unit within a category, used to enumerate every
/// unit of a category for the "convert to all" listing and the format hint.
class _CanonUnit {
  const _CanonUnit(this.label, this.factor, this.key);
  final String label;
  final double factor;

  /// A representative normalized alias, needed to route temperature conversions.
  final String key;
}

class ConvResult {
  const ConvResult({
    required this.value,
    required this.fromLabel,
    required this.toLabel,
    required this.category,
  });
  final double value;
  final String fromLabel;
  final String toLabel;
  final String category;
}

/// A single "value + label" line inside a [ConvAllResult].
class ConvAllItem {
  const ConvAllItem(this.value, this.label);
  final double value;
  final String label;
}

/// The result of converting one amount to every unit of a category.
class ConvAllResult {
  const ConvAllResult({
    required this.amount,
    required this.fromLabel,
    required this.category,
    required this.items,
  });
  final double amount;
  final String fromLabel;
  final String category;
  final List<ConvAllItem> items;
}

/// Either a single pairwise conversion or a "convert to all" listing.
class ConvOutput {
  const ConvOutput({this.single, this.all});
  final ConvResult? single;
  final ConvAllResult? all;
}

class UnitConverter {
  static const String _tempCategory = "temperature";

  /// alias (normalized, lowercase, alnum only) -> unit definition.
  /// Keys are kept mutually unambiguous across categories so each alias maps to
  /// exactly one unit.
  static final Map<String, _Unit> _aliases = _buildAliases();

  /// Human-readable label for the resolved unit alias, keyed the same way.
  static final Map<String, String> _labels = <String, String>{};

  /// category -> every canonical unit of that category, in registration order.
  static final Map<String, List<_CanonUnit>> _categoryUnits = <String, List<_CanonUnit>>{};

  /// Normalized category name/synonym -> canonical category key.
  static const Map<String, String> _categoryAliases = <String, String>{
    "length": "length", "distance": "length",
    "mass": "mass", "weight": "mass",
    "area": "area",
    "volume": "volume", "capacity": "volume",
    "speed": "speed", "velocity": "speed",
    "time": "time", "duration": "time",
    "data": "data", "digitalstorage": "data", "storage": "data",
    "energy": "energy",
    "pressure": "pressure",
    "angle": "angle",
    "temperature": "temperature", "temp": "temperature",
  };

  static String normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static Map<String, _Unit> _buildAliases() {
    final Map<String, _Unit> map = <String, _Unit>{};

    void reg(String category, double factor, String canonical, List<String> names) {
      final _Unit unit = _Unit(category, factor);
      String? repKey;
      for (final String name in names) {
        final String key = normalize(name);
        if (key.isEmpty) continue;
        repKey ??= key;
        map.putIfAbsent(key, () => unit);
        _labels.putIfAbsent(key, () => canonical);
      }
      if (repKey != null) {
        (_categoryUnits[category] ??= <_CanonUnit>[]).add(_CanonUnit(canonical, factor, repKey));
      }
    }

    // Length (base: meter)
    reg("length", 1, "m", <String>["m", "meter", "meters", "metre", "metres"]);
    reg("length", 1000, "km", <String>["km", "kilometer", "kilometers", "kilometre", "kilometres"]);
    reg("length", 0.01, "cm", <String>["cm", "centimeter", "centimeters", "centimetre", "centimetres"]);
    reg("length", 0.001, "mm", <String>["mm", "millimeter", "millimeters", "millimetre", "millimetres"]);
    reg("length", 1e-6, "µm", <String>["um", "micrometer", "micron", "microns"]);
    reg("length", 1e-9, "nm", <String>["nm", "nanometer", "nanometers"]);
    reg("length", 1609.344, "mi", <String>["mi", "mile", "miles"]);
    reg("length", 0.9144, "yd", <String>["yd", "yard", "yards"]);
    reg("length", 0.3048, "ft", <String>["ft", "foot", "feet"]);
    reg("length", 0.0254, "in", <String>["in", "inch", "inches"]);
    reg("length", 1852, "nmi", <String>["nmi", "nauticalmile", "nauticalmiles"]);

    // Mass (base: kilogram)
    reg("mass", 1, "kg", <String>["kg", "kilogram", "kilograms", "kilo", "kilos"]);
    reg("mass", 0.001, "g", <String>["g", "gram", "grams"]);
    reg("mass", 1e-6, "mg", <String>["mg", "milligram", "milligrams"]);
    reg("mass", 1e-9, "µg", <String>["ug", "microgram", "micrograms"]);
    reg("mass", 1000, "t", <String>["t", "tonne", "tonnes", "metricton"]);
    reg("mass", 0.45359237, "lb", <String>["lb", "lbs", "pound", "pounds"]);
    reg("mass", 0.028349523125, "oz", <String>["oz", "ounce", "ounces"]);
    reg("mass", 6.35029318, "st", <String>["st", "stone", "stones"]);

    // Area (base: square meter)
    reg("area", 1, "m²", <String>["m2", "sqm", "squaremeter", "squaremeters"]);
    reg("area", 1e6, "km²", <String>["km2", "sqkm", "squarekilometer"]);
    reg("area", 1e-4, "cm²", <String>["cm2", "sqcm"]);
    reg("area", 1e-6, "mm²", <String>["mm2", "sqmm"]);
    reg("area", 10000, "ha", <String>["ha", "hectare", "hectares"]);
    reg("area", 4046.8564224, "acre", <String>["acre", "acres"]);
    reg("area", 0.09290304, "ft²", <String>["sqft", "ft2", "squarefoot", "squarefeet"]);
    reg("area", 0.00064516, "in²", <String>["sqin", "in2", "squareinch"]);
    reg("area", 2589988.110336, "mi²", <String>["sqmi", "mi2", "squaremile"]);
    reg("area", 0.83612736, "yd²", <String>["sqyd", "yd2", "squareyard"]);

    // Volume (base: liter)
    reg("volume", 1, "L", <String>["l", "liter", "liters", "litre", "litres"]);
    reg("volume", 0.001, "mL", <String>["ml", "milliliter", "milliliters"]);
    reg("volume", 0.01, "cL", <String>["cl", "centiliter"]);
    reg("volume", 1000, "m³", <String>["m3", "cubicmeter", "cubicmeters"]);
    reg("volume", 0.001, "cm³", <String>["cm3", "cc", "cubiccentimeter"]);
    reg("volume", 3.785411784, "gal", <String>["gal", "gallon", "gallons", "usgal", "usgallon"]);
    reg("volume", 4.54609, "impgal", <String>["ukgal", "impgal", "imperialgallon"]);
    reg("volume", 0.946352946, "qt", <String>["qt", "quart", "quarts"]);
    reg("volume", 0.473176473, "pt", <String>["pt", "pint", "pints"]);
    reg("volume", 0.2365882365, "cup", <String>["cup", "cups"]);
    reg("volume", 0.0295735295625, "fl oz", <String>["floz", "fluidounce", "fluidounces"]);
    reg("volume", 0.01478676478125, "tbsp", <String>["tbsp", "tablespoon", "tablespoons"]);
    reg("volume", 0.00492892159375, "tsp", <String>["tsp", "teaspoon", "teaspoons"]);

    // Speed (base: meter per second)
    reg("speed", 1, "m/s", <String>["mps", "meterspersecond", "meterpersecond"]);
    reg("speed", 0.277777778, "km/h", <String>["kmh", "kph", "kmph", "kilometersperhour"]);
    reg("speed", 0.44704, "mph", <String>["mph", "milesperhour"]);
    reg("speed", 0.514444444, "knot", <String>["knot", "knots", "kn"]);
    reg("speed", 0.3048, "ft/s", <String>["fps", "feetpersecond"]);

    // Time (base: second)
    reg("time", 1, "s", <String>["s", "sec", "secs", "second", "seconds"]);
    reg("time", 0.001, "ms", <String>["ms", "millisecond", "milliseconds"]);
    reg("time", 60, "min", <String>["min", "mins", "minute", "minutes"]);
    reg("time", 3600, "h", <String>["h", "hr", "hrs", "hour", "hours"]);
    reg("time", 86400, "day", <String>["d", "day", "days"]);
    reg("time", 604800, "week", <String>["wk", "week", "weeks"]);
    reg("time", 2629800, "month", <String>["mo", "month", "months"]);
    reg("time", 31557600, "year", <String>["yr", "year", "years"]);

    // Digital storage (base: byte; kb/mb/gb are decimal SI, kib/mib/gib binary)
    reg("data", 1, "B", <String>["b", "byte", "bytes"]);
    reg("data", 0.125, "bit", <String>["bit", "bits"]);
    reg("data", 1000, "KB", <String>["kb", "kilobyte", "kilobytes"]);
    reg("data", 1024, "KiB", <String>["kib", "kibibyte"]);
    reg("data", 1e6, "MB", <String>["mb", "megabyte", "megabytes"]);
    reg("data", 1048576, "MiB", <String>["mib", "mebibyte"]);
    reg("data", 1e9, "GB", <String>["gb", "gigabyte", "gigabytes"]);
    reg("data", 1073741824, "GiB", <String>["gib", "gibibyte"]);
    reg("data", 1e12, "TB", <String>["tb", "terabyte", "terabytes"]);
    reg("data", 1099511627776, "TiB", <String>["tib", "tebibyte"]);
    reg("data", 1e15, "PB", <String>["pb", "petabyte", "petabytes"]);

    // Energy (base: joule)
    reg("energy", 1, "J", <String>["j", "joule", "joules"]);
    reg("energy", 1000, "kJ", <String>["kj", "kilojoule", "kilojoules"]);
    reg("energy", 4.184, "cal", <String>["cal", "calorie", "calories"]);
    reg("energy", 4184, "kcal", <String>["kcal", "kilocalorie", "kilocalories"]);
    reg("energy", 3600, "Wh", <String>["wh", "watthour", "watthours"]);
    reg("energy", 3.6e6, "kWh", <String>["kwh", "kilowatthour", "kilowatthours"]);
    reg("energy", 1055.05585262, "BTU", <String>["btu", "btus"]);

    // Pressure (base: pascal)
    reg("pressure", 1, "Pa", <String>["pa", "pascal", "pascals"]);
    reg("pressure", 1000, "kPa", <String>["kpa", "kilopascal"]);
    reg("pressure", 100, "hPa", <String>["hpa", "hectopascal"]);
    reg("pressure", 100000, "bar", <String>["bar", "bars"]);
    reg("pressure", 100, "mbar", <String>["mbar", "millibar"]);
    reg("pressure", 101325, "atm", <String>["atm", "atmosphere", "atmospheres"]);
    reg("pressure", 6894.757293, "psi", <String>["psi"]);
    reg("pressure", 133.322368, "mmHg", <String>["mmhg", "torr"]);

    // Angle (base: degree)
    reg("angle", 1, "°", <String>["deg", "degree", "degrees"]);
    reg("angle", 57.29577951308232, "rad", <String>["rad", "radian", "radians"]);
    reg("angle", 0.9, "grad", <String>["grad", "gradian", "gradians"]);
    reg("angle", 360, "turn", <String>["turn", "turns", "rev", "revolution", "revolutions"]);

    // Temperature (affine; factor unused)
    reg(_tempCategory, 1, "°C", <String>["c", "celsius", "centigrade"]);
    reg(_tempCategory, 1, "°F", <String>["f", "fahrenheit"]);
    reg(_tempCategory, 1, "K", <String>["k", "kelvin"]);
    reg(_tempCategory, 1, "°R", <String>["r", "rankine"]);

    return map;
  }

  static String categoryLabel(String category) {
    switch (category) {
      case "data":
        return "Digital storage";
      case "temperature":
        return "Temperature";
      default:
        return category[0].toUpperCase() + category.substring(1);
    }
  }

  /// Parses the input and either performs a single pairwise conversion
  /// (`10 km to miles`) or lists conversions to every unit of a category.
  ///
  /// - `10 km`        -> convert 10 m to every length unit.
  /// - `10 length`    -> convert from the category's default unit to all.
  /// - `10 km to mi`  -> single pairwise conversion.
  ///
  /// Throws a [FormatException] with a friendly message when the input can't
  /// be handled.
  static ConvOutput evaluate(String rawInput) {
    final String input = rawInput.trim();
    if (input.isEmpty) {
      throw const FormatException("Type something like 10 km to miles.");
    }

    final RegExpMatch? amountMatch = RegExp(r'^\s*(-?\d+(?:[.,]\d+)?)\s+(.+)$').firstMatch(input);
    if (amountMatch == null) {
      throw const FormatException("Start with a number, e.g. 10 km to miles.");
    }

    final double amount = double.tryParse((amountMatch.group(1) ?? "1").replaceAll(',', '.')) ?? 1;
    final String remainder = (amountMatch.group(2) ?? "").trim();
    final List<String> parts = remainder.split(RegExp(r'\s+(?:to|into|in|=|->)\s+'));

    if (parts.length == 1) {
      return ConvOutput(all: _convertToAll(amount, parts[0].trim()));
    }
    if (parts.length == 2) {
      return ConvOutput(single: _convertPair(amount, parts[0].trim(), parts[1].trim()));
    }
    throw const FormatException("Use a format like 10 km to miles.");
  }

  static ConvResult _convertPair(double amount, String fromRaw, String toRaw) {
    final String fromKey = normalize(fromRaw);
    final String toKey = normalize(toRaw);
    final _Unit? from = _aliases[fromKey];
    if (from == null) {
      throw FormatException("Unknown unit: $fromRaw");
    }
    final _Unit? to = _aliases[toKey];
    if (to == null) {
      throw FormatException("Unknown unit: $toRaw");
    }
    if (from.category != to.category) {
      throw FormatException(
        "Can't convert ${categoryLabel(from.category).toLowerCase()} to ${categoryLabel(to.category).toLowerCase()}.",
      );
    }

    final double result = from.category == _tempCategory
        ? _convertTemperature(amount, fromKey, toKey)
        : amount * from.factor / to.factor;

    return ConvResult(
      value: result,
      fromLabel: _labels[fromKey] ?? fromRaw,
      toLabel: _labels[toKey] ?? toRaw,
      category: from.category,
    );
  }

  /// `10 km` (single unit) or `10 length` (category name) -> conversions to
  /// every other unit of the resolved category.
  static ConvAllResult _convertToAll(double amount, String token) {
    final String key = normalize(token);
    final String category;
    final String fromKey;
    final String fromLabel;
    final double fromFactor;

    final _Unit? unit = _aliases[key];
    final String? namedCategory = _categoryAliases[key];
    if (unit != null) {
      category = unit.category;
      fromKey = key;
      fromLabel = _labels[key] ?? token;
      fromFactor = unit.factor;
    } else if (namedCategory != null) {
      final _CanonUnit def = _defaultUnit(namedCategory);
      category = namedCategory;
      fromKey = def.key;
      fromLabel = def.label;
      fromFactor = def.factor;
    } else {
      throw FormatException("Unknown unit or category: $token");
    }

    final List<ConvAllItem> items = <ConvAllItem>[];
    for (final _CanonUnit u in _categoryUnits[category] ?? const <_CanonUnit>[]) {
      if (u.label == fromLabel) continue;
      final double value = category == _tempCategory
          ? _convertTemperature(amount, fromKey, u.key)
          : amount * fromFactor / u.factor;
      items.add(ConvAllItem(value, u.label));
    }

    return ConvAllResult(amount: amount, fromLabel: fromLabel, category: category, items: items);
  }

  /// The default source unit for a category: its base unit (factor 1), falling
  /// back to the first registered unit.
  static _CanonUnit _defaultUnit(String category) {
    final List<_CanonUnit> units = _categoryUnits[category] ?? const <_CanonUnit>[];
    return units.firstWhere((_CanonUnit u) => u.factor == 1, orElse: () => units.first);
  }

  /// category -> the canonical labels of every unit in it (for the format hint).
  static List<MapEntry<String, List<String>>> categoryFormats() {
    return _categoryUnits.entries
        .map((MapEntry<String, List<_CanonUnit>> e) =>
            MapEntry<String, List<String>>(e.key, e.value.map((_CanonUnit u) => u.label).toList()))
        .toList();
  }

  static double _convertTemperature(double value, String fromKey, String toKey) {
    // Everything routes through Celsius.
    double celsius;
    switch (fromKey) {
      case "f":
      case "fahrenheit":
        celsius = (value - 32) * 5 / 9;
        break;
      case "k":
      case "kelvin":
        celsius = value - 273.15;
        break;
      case "r":
      case "rankine":
        celsius = (value - 491.67) * 5 / 9;
        break;
      default:
        celsius = value;
    }
    switch (toKey) {
      case "f":
      case "fahrenheit":
        return celsius * 9 / 5 + 32;
      case "k":
      case "kelvin":
        return celsius + 273.15;
      case "r":
      case "rankine":
        return (celsius + 273.15) * 9 / 5;
      default:
        return celsius;
    }
  }

  static String formatNumber(double value) {
    if (!value.isFinite) return "—";
    final double abs = value.abs();
    if (abs != 0 && (abs >= 1e12 || abs < 1e-4)) {
      return value.toStringAsExponential(4);
    }
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    String out = value.toStringAsFixed(6);
    out = out.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return out;
  }
}

class UniversalConverterWidget extends StatefulWidget {
  const UniversalConverterWidget({super.key});

  @override
  State<UniversalConverterWidget> createState() => _UniversalConverterWidgetState();
}

class _UniversalConverterWidgetState extends State<UniversalConverterWidget> {
  static const String _queryKey = "unitConverterQuery";

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  ConvResult? _result;
  ConvAllResult? _allResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    final String saved = (Boxes.pref.getString(_queryKey) ?? "").trim();
    _controller.text = saved.isEmpty ? "10 km to miles" : saved;
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
      _recompute();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    Boxes.updateSettings(_queryKey, _controller.text.trim());
    _recompute();
  }

  void _recompute() {
    try {
      final ConvOutput out = UnitConverter.evaluate(_controller.text);
      setState(() {
        _result = out.single;
        _allResult = out.all;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _result = null;
        _allResult = null;
        _error = e.message;
      });
    }
  }

  void _copyResult() {
    final ConvResult? result = _result;
    if (result == null) return;
    Clipboard.setData(ClipboardData(text: UnitConverter.formatNumber(result.value)));
  }

  void _copyValue(double value) {
    Clipboard.setData(ClipboardData(text: UnitConverter.formatNumber(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: C.stretch,
        children: <Widget>[
          const PanelHeader(
            title: "Unit Converter",
            icon: Icons.straighten_rounded,
          ),
          Flexible(
            child: WindowsScrollView(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(12),
                children: <Widget>[
                  _buildInput(),
                  const SizedBox(height: 12),
                  _buildResultCard(),
                  const SizedBox(height: 10),
                  _buildHint(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    final Color accent = Design.accent;
    return TextField(
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        isDense: true,
        hintText: "10 km to miles",
        prefixIcon: Icon(Icons.straighten_rounded, size: 16, color: accent),
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
    );
  }

  Widget _buildResultCard() {
    final Color accent = Design.accent;
    final ConvResult? result = _result;
    final ConvAllResult? all = _allResult;

    if (all != null) {
      return _buildAllCard(all);
    }

    if (result == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        decoration: BoxDecoration(
          color: Design.text.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            _error ?? "…",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Design.baseFontSize + 2,
              color: (_error != null ? Colors.orangeAccent : Design.text).withAlpha(190),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: _copyResult,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  Center(
                    child: Text(
                      "${UnitConverter.formatNumber(result.value)} ${result.toLabel}",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Design.text,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      "${UnitConverter.categoryLabel(result.category)}  ·  ${result.fromLabel} → ${result.toLabel}",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        color: Design.text.withAlpha(140),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Icon(Icons.content_copy_rounded, size: 14, color: Design.text.withAlpha(130)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllCard(ConvAllResult all) {
    final Color accent = Design.accent;
    return Container(
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: C.stretch,
          children: <Widget>[
            Text(
              "${UnitConverter.formatNumber(all.amount)} ${all.fromLabel}  ·  ${UnitConverter.categoryLabel(all.category)}",
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 6),
            for (final ConvAllItem item in all.items)
              InkWell(
                onTap: () => _copyValue(item.value),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          UnitConverter.formatNumber(item.value),
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 2,
                            fontWeight: FontWeight.w600,
                            color: Design.text,
                          ),
                        ),
                      ),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: Design.baseFontSize,
                          color: Design.text.withAlpha(150),
                        ),
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

  Widget _buildHint() {
    return Column(
      crossAxisAlignment: C.stretch,
      children: <Widget>[
        Text(
          "Type an amount plus a unit or category for all conversions, e.g. 10 km or 10 length.",
          style: TextStyle(
            fontSize: Design.baseFontSize,
            color: Design.text.withAlpha(120),
          ),
        ),
        const SizedBox(height: 8),
        for (final MapEntry<String, List<String>> e in UnitConverter.categoryFormats())
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text.rich(
              TextSpan(
                children: <TextSpan>[
                  TextSpan(
                    text: "${UnitConverter.categoryLabel(e.key)}: ",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Design.text.withAlpha(160),
                    ),
                  ),
                  TextSpan(
                    text: e.value.join(", "),
                    style: TextStyle(color: Design.text.withAlpha(110)),
                  ),
                ],
              ),
              style: TextStyle(fontSize: Design.baseFontSize),
            ),
          ),
      ],
    );
  }
}
