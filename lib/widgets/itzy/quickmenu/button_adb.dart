import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

/// Top-bar launcher for the ADB Control panel.
///
/// Ports the controls/settings from the PowerToys CmdPal `AdbExtension`:
/// device-wide toggles (Wi-Fi, mobile data, airplane, animations, layout
/// bounds, touch coordinates), one-shot actions (screenshot, install APK,
/// reboot, key events), system & package deep links, and per-package actions
/// (launch/restart/kill/force-stop/clear-data/permissions/uninstall).
class AdbButton extends StatelessWidget {
  const AdbButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "ADB Control",
      icon: const Icon(Icons.android),
      child: () => const AdbPanel(),
    );
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class _AdbResult {
  const _AdbResult(this.stdout, this.stderr, this.ok);
  final String stdout;
  final String stderr;
  final bool ok;
}

class _AdbDevice {
  const _AdbDevice(this.serial, this.state);
  final String serial;
  final String state;
  bool get isReady => state == "device";
}

class _DeviceStatus {
  const _DeviceStatus({
    this.model,
    this.wifi,
    this.mobileData,
    this.airplane,
    this.animations,
    this.touches,
    this.layoutBounds,
    this.darkMode,
    this.stayAwake,
  });

  final String? model;
  final bool? wifi;
  final bool? mobileData;
  final bool? airplane;
  final bool? animations;
  final bool? touches;
  final bool? layoutBounds;
  final bool? darkMode;
  final bool? stayAwake;
}

class _AdbPackage {
  const _AdbPackage(this.name, this.favorite);
  final String name;
  final bool favorite;
}

/// Thin wrapper around the `adb` executable. All commands run through here so
/// the executable path override and the active device serial are applied once.
class _AdbService {
  static const String adbPathKey = "adbExecutablePath";
  static const String screenshotFolderKey = "adbScreenshotFolder";
  static const String apkFolderKey = "adbApkFolder";
  static const String skipUninstallKey = "adbSkipUninstallConfirm";
  static const String favoritesKey = "adbFavoritePackages";

  static String get exe {
    final String custom = (Boxes.pref.getString(adbPathKey) ?? "").trim();
    return custom.isEmpty ? "adb" : custom;
  }

  static Future<_AdbResult> run(List<String> args, {String? serial}) async {
    final List<String> fullArgs = <String>[
      if (serial != null) ...<String>["-s", serial],
      ...args,
    ];
    try {
      final ProcessResult result = await Process.run(exe, fullArgs, runInShell: false);
      final String out = (result.stdout ?? "").toString();
      final String err = (result.stderr ?? "").toString();
      final bool hasError = result.exitCode != 0 || err.toLowerCase().contains("error:");
      return _AdbResult(
        out.trim(),
        hasError ? (err.trim().isEmpty ? "adb exited with code ${result.exitCode}" : err.trim()) : "",
        !hasError,
      );
    } on ProcessException catch (e) {
      if (e.errorCode == 2) {
        return const _AdbResult(
          "",
          "ADB not found. Put adb.exe on your PATH or set its path in settings.",
          false,
        );
      }
      return _AdbResult("", e.message, false);
    } catch (e) {
      return _AdbResult("", e.toString(), false);
    }
  }
}

// ---------------------------------------------------------------------------
// Panel
// ---------------------------------------------------------------------------

enum _AdbView { main, packages, packageActions, settings }

class AdbPanel extends StatefulWidget {
  const AdbPanel({super.key});

  @override
  State<AdbPanel> createState() => _AdbPanelState();
}

class _AdbPanelState extends State<AdbPanel> {
  _AdbView _view = _AdbView.main;

  // Status / devices
  List<_AdbDevice> _devices = <_AdbDevice>[];
  String? _selectedSerial;
  _DeviceStatus? _status;
  bool _loadingStatus = true;
  bool _busy = false;

  // Inline feedback strip
  String? _message;
  bool _messageIsError = false;
  Timer? _messageTimer;

  // Packages
  List<_AdbPackage>? _packages;
  bool _loadingPackages = false;
  String? _activePackage;
  List<String> _favorites = <String>[];

  // Deep link inputs
  final TextEditingController _deepLinkController = TextEditingController();
  final TextEditingController _packageDeepLinkController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  bool _showPackageDeepLink = false;

  // Settings inputs
  final TextEditingController _adbPathController = TextEditingController();
  final TextEditingController _screenshotFolderController = TextEditingController();
  final TextEditingController _apkFolderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _favorites = Boxes.pref.getStringList(_AdbService.favoritesKey) ?? <String>[];
    _adbPathController.text = Boxes.pref.getString(_AdbService.adbPathKey) ?? "";
    _screenshotFolderController.text = Boxes.pref.getString(_AdbService.screenshotFolderKey) ?? "";
    _apkFolderController.text = Boxes.pref.getString(_AdbService.apkFolderKey) ?? "";
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_refreshDevices());
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _deepLinkController.dispose();
    _packageDeepLinkController.dispose();
    _searchController.dispose();
    _adbPathController.dispose();
    _screenshotFolderController.dispose();
    _apkFolderController.dispose();
    super.dispose();
  }

  bool get _skipUninstallConfirm => Boxes.pref.getBool(_AdbService.skipUninstallKey) ?? false;

  // -------------------------------------------------------------------------
  // Feedback helpers
  // -------------------------------------------------------------------------

  void _flash(String message, {bool error = false}) {
    _messageTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
    _messageTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _message = null);
    });
  }

  Future<void> _exec(List<String> args, {required String success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final _AdbResult result = await _AdbService.run(args, serial: _selectedSerial);
    if (!mounted) return;
    setState(() => _busy = false);
    _flash(result.ok ? success : (result.stderr.isEmpty ? "Command failed" : result.stderr), error: !result.ok);
  }

  // -------------------------------------------------------------------------
  // Device discovery + status
  // -------------------------------------------------------------------------

  Future<void> _refreshDevices() async {
    setState(() => _loadingStatus = true);
    final _AdbResult result = await _AdbService.run(<String>["devices"]);
    if (!mounted) return;

    final List<_AdbDevice> devices = <_AdbDevice>[];
    if (result.ok) {
      final List<String> lines = result.stdout.split("\n");
      for (final String raw in lines.skip(1)) {
        final String line = raw.trim();
        if (line.isEmpty) continue;
        final List<String> parts = line.split(RegExp(r"\s+"));
        if (parts.length >= 2) devices.add(_AdbDevice(parts[0], parts[1]));
      }
    }

    String? selected = _selectedSerial;
    final bool stillThere = devices.any((_AdbDevice d) => d.serial == selected && d.isReady);
    if (!stillThere) {
      selected = devices
          .firstWhere(
            (_AdbDevice d) => d.isReady,
            orElse: () => const _AdbDevice("", ""),
          )
          .serial;
      if (selected.isEmpty) selected = null;
    }

    setState(() {
      _devices = devices;
      _selectedSerial = selected;
      if (!result.ok) _flash(result.stderr, error: true);
    });

    await _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    if (_selectedSerial == null) {
      if (mounted) {
        setState(() {
          _status = null;
          _loadingStatus = false;
        });
      }
      return;
    }
    setState(() => _loadingStatus = true);

    const String command = "getprop ro.product.model; "
        "settings get global wifi_on; "
        "settings get global mobile_data; "
        "settings get global airplane_mode_on; "
        "settings get global window_animation_scale; "
        "settings get system show_touches; "
        "getprop debug.layout; "
        "cmd uimode night; "
        "settings get global stay_on_while_plugged_in";

    final _AdbResult result = await _AdbService.run(<String>["shell", command], serial: _selectedSerial);
    if (!mounted) return;

    final List<String> lines = result.stdout.split("\n");
    String at(int index) => index < lines.length ? lines[index].trim() : "";
    bool isOne(String value) => value == "1";
    bool? notZero(String value) {
      if (value.isEmpty || value == "null") return null;
      return value != "0" && value != "0.0";
    }

    setState(() {
      _loadingStatus = false;
      _status = _DeviceStatus(
        model: at(0).isEmpty || at(0) == "null" ? null : at(0),
        wifi: isOne(at(1)),
        mobileData: isOne(at(2)),
        airplane: isOne(at(3)),
        animations: notZero(at(4)),
        touches: isOne(at(5)),
        layoutBounds: at(6) == "true",
        darkMode: at(7).toLowerCase().contains("yes"),
        stayAwake: notZero(at(8)),
      );
    });
  }

  // -------------------------------------------------------------------------
  // Device toggles
  // -------------------------------------------------------------------------

  Future<void> _toggle(List<List<String>> commands, {required String success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    _AdbResult last = const _AdbResult("", "", true);
    for (final List<String> args in commands) {
      last = await _AdbService.run(args, serial: _selectedSerial);
      if (!last.ok) break;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _flash(last.ok ? success : (last.stderr.isEmpty ? "Command failed" : last.stderr), error: !last.ok);
    await _refreshStatus();
  }

  Future<void> _toggleWifi() {
    final bool target = !(_status?.wifi ?? false);
    return _toggle(
      <List<String>>[
        <String>["shell", "svc", "wifi", target ? "enable" : "disable"]
      ],
      success: "Wi-Fi ${target ? "enabled" : "disabled"}",
    );
  }

  Future<void> _toggleMobileData() {
    final bool target = !(_status?.mobileData ?? false);
    return _toggle(
      <List<String>>[
        <String>["shell", "svc", "data", target ? "enable" : "disable"]
      ],
      success: "Mobile data ${target ? "enabled" : "disabled"}",
    );
  }

  Future<void> _toggleAirplane() async {
    if (_busy) return;
    final bool enable = !(_status?.airplane ?? false);
    setState(() => _busy = true);
    final _AdbResult sdkResult = await _AdbService.run(
      <String>["shell", "getprop", "ro.build.version.sdk"],
      serial: _selectedSerial,
    );
    final int sdk = int.tryParse(sdkResult.stdout.trim()) ?? 0;

    _AdbResult write;
    if (sdk >= 30) {
      write = await _AdbService.run(
        <String>["shell", "cmd", "connectivity", "airplane-mode", enable ? "enable" : "disable"],
        serial: _selectedSerial,
      );
    } else {
      write = await _AdbService.run(
        <String>["shell", "settings", "put", "global", "airplane_mode_on", enable ? "1" : "0"],
        serial: _selectedSerial,
      );
      if (write.ok) {
        write = await _AdbService.run(
          <String>[
            "shell",
            "am",
            "broadcast",
            "-a",
            "android.intent.action.AIRPLANE_MODE",
            "--ez",
            "state",
            enable ? "true" : "false"
          ],
          serial: _selectedSerial,
        );
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _flash(write.ok ? "Airplane mode ${enable ? "enabled" : "disabled"}" : write.stderr, error: !write.ok);
    await _refreshStatus();
  }

  Future<void> _toggleAnimations() {
    final bool target = !(_status?.animations ?? false);
    final String value = target ? "1" : "0";
    return _toggle(
      <List<String>>[
        <String>["shell", "settings", "put", "global", "window_animation_scale", value],
        <String>["shell", "settings", "put", "global", "transition_animation_scale", value],
        <String>["shell", "settings", "put", "global", "animator_duration_scale", value],
      ],
      success: "Animations ${target ? "enabled" : "disabled"}",
    );
  }

  Future<void> _toggleLayoutBounds() {
    final bool target = !(_status?.layoutBounds ?? false);
    return _toggle(
      <List<String>>[
        <String>["shell", "setprop", "debug.layout", target ? "true" : "false"],
        <String>["shell", "service", "call", "activity", "1599295570"],
      ],
      success: "Layout bounds ${target ? "enabled" : "disabled"}",
    );
  }

  Future<void> _toggleTouches() {
    final bool target = !(_status?.touches ?? false);
    return _toggle(
      <List<String>>[
        <String>["shell", "settings", "put", "system", "show_touches", target ? "1" : "0"]
      ],
      success: "Touch coordinates ${target ? "enabled" : "disabled"}",
    );
  }

  Future<void> _toggleDarkMode() {
    final bool target = !(_status?.darkMode ?? false);
    return _toggle(
      <List<String>>[
        <String>["shell", "cmd", "uimode", "night", target ? "yes" : "no"]
      ],
      success: "Dark mode ${target ? "enabled" : "disabled"}",
    );
  }

  Future<void> _toggleStayAwake() {
    final bool target = !(_status?.stayAwake ?? false);
    return _toggle(
      <List<String>>[
        <String>["shell", "settings", "put", "global", "stay_on_while_plugged_in", target ? "3" : "0"]
      ],
      success: "Stay awake ${target ? "enabled" : "disabled"}",
    );
  }

  // -------------------------------------------------------------------------
  // One-shot actions
  // -------------------------------------------------------------------------

  Future<void> _takeScreenshot() async {
    if (_busy) return;
    setState(() => _busy = true);
    const String devicePath = "/sdcard/tabame_screenshot.png";
    final _AdbResult capture =
        await _AdbService.run(<String>["shell", "screencap", "-p", devicePath], serial: _selectedSerial);
    if (!capture.ok) {
      if (!mounted) return;
      setState(() => _busy = false);
      _flash(capture.stderr.isEmpty ? "Capture failed" : capture.stderr, error: true);
      return;
    }
    final String localPath = _buildScreenshotPath();
    final _AdbResult pull = await _AdbService.run(<String>["pull", devicePath, localPath], serial: _selectedSerial);
    unawaited(_AdbService.run(<String>["shell", "rm", devicePath], serial: _selectedSerial));
    if (!mounted) return;
    setState(() => _busy = false);
    _flash(pull.ok ? "Saved: $localPath" : (pull.stderr.isEmpty ? "Pull failed" : pull.stderr), error: !pull.ok);
  }

  String _buildScreenshotPath() {
    String folder = (Boxes.pref.getString(_AdbService.screenshotFolderKey) ?? "").trim();
    if (folder.isEmpty || !Directory(folder).existsSync()) {
      final String userProfile = Platform.environment["USERPROFILE"] ?? "";
      folder = "$userProfile\\Pictures";
      if (!Directory(folder).existsSync()) folder = userProfile;
    }
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, "0");
    final String stamp =
        "${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}";
    return "$folder\\screenshot_$stamp.png";
  }

  Future<void> _installApk() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{"Android Package (*.apk)": "*.apk"}
      ..defaultFilterIndex = 0
      ..title = "Select APK to install";
    final String apkFolder = (Boxes.pref.getString(_AdbService.apkFolderKey) ?? "").trim();
    if (apkFolder.isNotEmpty && Directory(apkFolder).existsSync()) {
      picker.initialDirectory = apkFolder;
    }
    final File? file = picker.getFile();
    Timer(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
    if (file == null) return;
    await _exec(<String>["install", "-r", file.path], success: "Installed ${file.path.split(RegExp(r"[\\/]")).last}");
  }

  Future<void> _launchSystemDeepLink() async {
    final String url = _deepLinkController.text.trim();
    if (url.isEmpty) {
      _flash("Enter a deep link first", error: true);
      return;
    }
    await _exec(
      <String>["shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", url],
      success: "Launched: $url",
    );
  }

  // -------------------------------------------------------------------------
  // Packages
  // -------------------------------------------------------------------------

  Future<void> _loadPackages() async {
    setState(() => _loadingPackages = true);
    final _AdbResult result =
        await _AdbService.run(<String>["shell", "pm", "list", "packages", "-3"], serial: _selectedSerial);
    if (!mounted) return;

    final List<String> names = <String>[];
    if (result.ok) {
      for (final String raw in result.stdout.split("\n")) {
        final String line = raw.trim();
        if (line.startsWith("package:")) names.add(line.substring("package:".length));
      }
      names.sort();
    }

    setState(() {
      _loadingPackages = false;
      _packages = names.map((String name) => _AdbPackage(name, _favorites.contains(name))).toList(growable: false);
      if (!result.ok) _flash(result.stderr, error: true);
    });
  }

  void _toggleFavorite(String name) {
    setState(() {
      if (_favorites.contains(name)) {
        _favorites.remove(name);
      } else {
        _favorites.add(name);
      }
      _packages =
          _packages?.map((_AdbPackage p) => _AdbPackage(p.name, _favorites.contains(p.name))).toList(growable: false);
    });
    Boxes.updateSettings(_AdbService.favoritesKey, _favorites);
  }

  Future<String?> _resolveLauncherActivity(String packageName) async {
    final _AdbResult result = await _AdbService.run(
      <String>[
        "shell",
        "cmd",
        "package",
        "resolve-activity",
        "--brief",
        "-c",
        "android.intent.category.LAUNCHER",
        packageName
      ],
      serial: _selectedSerial,
    );
    if (!result.ok) return null;
    for (final String raw in result.stdout.split("\n")) {
      final String line = raw.trim();
      if (line.startsWith(packageName)) return line;
    }
    return null;
  }

  Future<void> _launchPackage(String packageName) async {
    if (_busy) return;
    setState(() => _busy = true);
    final String? activity = await _resolveLauncherActivity(packageName);
    if (activity == null) {
      if (!mounted) return;
      setState(() => _busy = false);
      _flash("Could not resolve launcher activity", error: true);
      return;
    }
    setState(() => _busy = false);
    await _exec(<String>["shell", "am", "start", "-n", activity], success: "Launched $packageName");
  }

  Future<void> _restartPackage(String packageName) async {
    if (_busy) return;
    setState(() => _busy = true);
    final _AdbResult stop =
        await _AdbService.run(<String>["shell", "am", "force-stop", packageName], serial: _selectedSerial);
    if (!stop.ok) {
      if (!mounted) return;
      setState(() => _busy = false);
      _flash(stop.stderr.isEmpty ? "Failed to stop app" : stop.stderr, error: true);
      return;
    }
    final String? activity = await _resolveLauncherActivity(packageName);
    setState(() => _busy = false);
    if (activity == null) {
      _flash("Stopped, but could not resolve launcher activity", error: true);
      return;
    }
    await _exec(<String>["shell", "am", "start", "-n", activity], success: "Restarted $packageName");
  }

  Future<void> _clearAndRestart(String packageName) async {
    if (_busy) return;
    setState(() => _busy = true);
    final _AdbResult clear =
        await _AdbService.run(<String>["shell", "pm", "clear", packageName], serial: _selectedSerial);
    if (!clear.ok) {
      if (!mounted) return;
      setState(() => _busy = false);
      _flash(clear.stderr.isEmpty ? "Failed to clear data" : clear.stderr, error: true);
      return;
    }
    final String? activity = await _resolveLauncherActivity(packageName);
    setState(() => _busy = false);
    if (activity == null) {
      _flash("Cleared, but could not resolve launcher activity", error: true);
      return;
    }
    await _exec(<String>["shell", "am", "start", "-n", activity], success: "Cleared & restarted $packageName");
  }

  Future<void> _changePermissions(String packageName, {required bool grant}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final _AdbResult dump =
        await _AdbService.run(<String>["shell", "dumpsys", "package", packageName], serial: _selectedSerial);
    if (!dump.ok) {
      if (!mounted) return;
      setState(() => _busy = false);
      _flash(dump.stderr.isEmpty ? "Failed to read package info" : dump.stderr, error: true);
      return;
    }
    final List<String> permissions = _parseRuntimePermissions(dump.stdout, onlyGranted: !grant);
    if (permissions.isEmpty) {
      if (!mounted) return;
      setState(() => _busy = false);
      _flash(grant ? "No runtime permissions found" : "No granted runtime permissions found");
      return;
    }
    int changed = 0;
    for (final String permission in permissions) {
      final _AdbResult result = await _AdbService.run(
        <String>["shell", "pm", grant ? "grant" : "revoke", packageName, permission],
        serial: _selectedSerial,
      );
      if (result.ok) changed++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _flash("${grant ? "Granted" : "Revoked"} $changed/${permissions.length} permissions");
  }

  List<String> _parseRuntimePermissions(String dump, {required bool onlyGranted}) {
    final List<String> result = <String>[];
    bool inSection = false;
    for (final String raw in dump.split("\n")) {
      final String line = raw.trim();
      if (line.startsWith("runtime permissions:")) {
        inSection = true;
        continue;
      }
      if (!inSection) continue;
      final int colon = line.indexOf(":");
      if (colon > 0 && line.startsWith("android.permission.")) {
        if (!onlyGranted || line.contains("granted=true")) result.add(line.substring(0, colon));
      } else if (line.isNotEmpty && !line.startsWith("android.")) {
        break;
      }
    }
    return result;
  }

  Future<void> _uninstallPackage(String packageName) async {
    final _AdbResult result =
        await _AdbService.run(<String>["shell", "pm", "uninstall", packageName], serial: _selectedSerial);
    if (!mounted) return;
    if (result.ok) {
      _favorites.remove(packageName);
      Boxes.updateSettings(_AdbService.favoritesKey, _favorites);
      setState(() {
        _packages = null;
        _view = _AdbView.packages;
        _activePackage = null;
      });
      _flash("Uninstalled $packageName");
      unawaited(_loadPackages());
    } else {
      _flash(result.stderr.isEmpty ? "Failed to uninstall" : result.stderr, error: true);
    }
  }

  void _confirmUninstall(String packageName) {
    if (_skipUninstallConfirm) {
      unawaited(_uninstallPackage(packageName));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title:
              Text("Uninstall $packageName?", style: TextStyle(fontSize: Design.baseFontSize + 3, color: Design.text)),
          content: Text(
            "This removes the app and all its data from the device.",
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(190)),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text("Cancel", style: TextStyle(color: Design.text.withAlpha(190))),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(_uninstallPackage(packageName));
              },
              child: const Text("Uninstall", style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchPackageDeepLink(String packageName) async {
    final String url = _packageDeepLinkController.text.trim();
    if (url.isEmpty) {
      _flash("Enter a deep link first", error: true);
      return;
    }
    await _exec(
      <String>["shell", "am", "start", "-p", packageName, "-a", "android.intent.action.VIEW", "-d", url],
      success: "Opened: $url",
    );
  }

  // -------------------------------------------------------------------------
  // Settings pickers
  // -------------------------------------------------------------------------

  Future<void> _pickFolder(TextEditingController controller, String key, String title) async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final DirectoryPicker picker = DirectoryPicker()..title = title;
    final Directory? directory = picker.getDirectory();
    Timer(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
    if (directory == null || directory.path.isEmpty) return;
    setState(() => controller.text = directory.path);
    Boxes.updateSettings(key, directory.path);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(),
          if (_busy || _loadingStatus || _loadingPackages) const LinearProgressIndicator(minHeight: 1.5),
          if (_message != null) _buildMessageStrip(),
          Flexible(child: _buildBody()),
        ],
      ),
    );
  }

  PanelHeader _buildHeader() {
    switch (_view) {
      case _AdbView.main:
        return PanelHeader(
          title: "ADB Control",
          icon: Icons.android,
          buttonPressed: _refreshDevices,
          buttonIcon: Icons.refresh_rounded,
          buttonTooltip: "Refresh devices",
          extraActions: <Widget>[
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: "Settings",
              onPressed: () => setState(() => _view = _AdbView.settings),
            ),
          ],
        );
      case _AdbView.packages:
        return PanelHeader(
          title: "Packages",
          icon: Icons.apps_rounded,
          buttonPressed: () => setState(() => _view = _AdbView.main),
          buttonIcon: Icons.arrow_back_rounded,
          buttonTooltip: "Back",
          extraActions: <Widget>[
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: "Reload packages",
              onPressed: () => unawaited(_loadPackages()),
            ),
          ],
        );
      case _AdbView.packageActions:
        return PanelHeader(
          title: _activePackage ?? "Package",
          icon: Icons.android,
          buttonPressed: () => setState(() {
            _view = _AdbView.packages;
            _showPackageDeepLink = false;
          }),
          buttonIcon: Icons.arrow_back_rounded,
          buttonTooltip: "Back",
          extraActions: <Widget>[
            IconButton(
              icon: Icon(
                (_activePackage != null && _favorites.contains(_activePackage))
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
              ),
              tooltip: "Favorite",
              onPressed: _activePackage == null ? null : () => _toggleFavorite(_activePackage!),
            ),
          ],
        );
      case _AdbView.settings:
        return PanelHeader(
          title: "ADB Settings",
          icon: Icons.tune_rounded,
          buttonPressed: () => setState(() => _view = _AdbView.main),
          buttonIcon: Icons.arrow_back_rounded,
          buttonTooltip: "Back",
        );
    }
  }

  Widget _buildMessageStrip() {
    final Color color = _messageIsError ? Colors.redAccent : Design.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      color: color.withAlpha(18),
      child: Row(
        children: <Widget>[
          Icon(_messageIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.baseFontSize, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_view) {
      case _AdbView.main:
        return _buildMainView();
      case _AdbView.packages:
        return _buildPackagesView();
      case _AdbView.packageActions:
        return _buildPackageActionsView();
      case _AdbView.settings:
        return _buildSettingsView();
    }
  }

  // -------------------------------------------------------------------------
  // Main view
  // -------------------------------------------------------------------------

  Widget _buildMainView() {
    final bool connected = _selectedSerial != null;
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildDeviceCard(),
          if (!connected) ...<Widget>[
            const SizedBox(height: 8),
            _buildEmptyDeviceState(),
          ] else ...<Widget>[
            const SizedBox(height: 10),
            _buildSectionLabel(label: "Controls", icon: Icons.toggle_on_rounded),
            const SizedBox(height: 8),
            _buildToggleGrid(),
            const SizedBox(height: 12),
            _buildSectionLabel(label: "Actions", icon: Icons.bolt_rounded),
            const SizedBox(height: 8),
            _buildActionGrid(),
            const SizedBox(height: 12),
            _buildSectionLabel(label: "Navigation", icon: Icons.gamepad_outlined),
            const SizedBox(height: 8),
            _buildNavGrid(),
            const SizedBox(height: 12),
            _buildSectionLabel(label: "Deep Link", icon: Icons.link_rounded),
            const SizedBox(height: 8),
            _buildDeepLinkCard(),
            const SizedBox(height: 12),
            _buildPackagesEntry(),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceCard() {
    final bool connected = _selectedSerial != null;
    final String title = connected ? (_status?.model ?? _selectedSerial ?? "Device") : "No device connected";
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: connected ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: connected ? Design.accent.withAlpha(30) : Design.text.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: connected ? Colors.greenAccent.shade400 : Design.text.withAlpha(70),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: Design.text),
                ),
              ),
              if (connected && _status?.model != null)
                Text(
                  _selectedSerial!,
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140)),
                ),
            ],
          ),
          if (_devices.length > 1) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _devices.map((_AdbDevice device) => _buildDeviceChip(device)).toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceChip(_AdbDevice device) {
    final bool selected = device.serial == _selectedSerial;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: !device.isReady
          ? null
          : () {
              setState(() => _selectedSerial = device.serial);
              unawaited(_refreshStatus());
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Design.accent.withAlpha(28) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Design.accent.withAlpha(80) : Design.text.withAlpha(16)),
        ),
        child: Text(
          "${device.serial}${device.isReady ? "" : " (${device.state})"}",
          style: TextStyle(
            fontSize: Design.baseFontSize,
            fontWeight: FontWeight.w600,
            color: selected ? Design.accent : Design.text.withAlpha(170),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDeviceState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.phonelink_erase_rounded, size: 30, color: Design.text.withAlpha(110)),
          const SizedBox(height: 10),
          Text(
            "No device detected",
            style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: Design.text),
          ),
          const SizedBox(height: 4),
          Text(
            "Connect a device with USB debugging enabled, then refresh.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150)),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleGrid() {
    final _DeviceStatus? status = _status;
    final List<Widget> tiles = <Widget>[
      _ToggleTile(icon: Icons.wifi_rounded, label: "Wi-Fi", value: status?.wifi, onTap: _toggleWifi),
      _ToggleTile(
          icon: Icons.network_cell_rounded, label: "Mobile Data", value: status?.mobileData, onTap: _toggleMobileData),
      _ToggleTile(
          icon: Icons.airplanemode_active_rounded, label: "Airplane", value: status?.airplane, onTap: _toggleAirplane),
      _ToggleTile(
          icon: Icons.animation_rounded, label: "Animations", value: status?.animations, onTap: _toggleAnimations),
      _ToggleTile(
          icon: Icons.grid_4x4_rounded,
          label: "Layout Bounds",
          value: status?.layoutBounds,
          onTap: _toggleLayoutBounds),
      _ToggleTile(icon: Icons.touch_app_rounded, label: "Show Touches", value: status?.touches, onTap: _toggleTouches),
      _ToggleTile(icon: Icons.dark_mode_rounded, label: "Dark Mode", value: status?.darkMode, onTap: _toggleDarkMode),
      _ToggleTile(icon: Icons.coffee_rounded, label: "Stay Awake", value: status?.stayAwake, onTap: _toggleStayAwake),
    ];
    return _buildGrid(tiles, columns: 3);
  }

  Widget _buildActionGrid() {
    final List<Widget> tiles = <Widget>[
      _ActionTile(icon: Icons.photo_camera_rounded, label: "Screenshot", onTap: _takeScreenshot),
      _ActionTile(icon: Icons.download_rounded, label: "Install APK", onTap: _installApk),
      _ActionTile(
        icon: Icons.restart_alt_rounded,
        label: "Reboot",
        onTap: () => _exec(<String>["reboot"], success: "Rebooting device"),
      ),
      _ActionTile(
        icon: Icons.power_settings_new_rounded,
        label: "Power",
        onTap: () => _exec(<String>["shell", "input", "keyevent", "26"], success: "Sent power key"),
      ),
      _ActionTile(
        icon: Icons.volume_up_rounded,
        label: "Vol +",
        onTap: () => _exec(<String>["shell", "input", "keyevent", "24"], success: "Volume up"),
      ),
      _ActionTile(
        icon: Icons.volume_down_rounded,
        label: "Vol -",
        onTap: () => _exec(<String>["shell", "input", "keyevent", "25"], success: "Volume down"),
      ),
    ];
    return _buildGrid(tiles, columns: 3);
  }

  Widget _buildNavGrid() {
    final List<Widget> tiles = <Widget>[
      _ActionTile(
        icon: Icons.arrow_back_rounded,
        label: "Back",
        onTap: () => _exec(<String>["shell", "input", "keyevent", "4"], success: "Back"),
      ),
      _ActionTile(
        icon: Icons.home_rounded,
        label: "Home",
        onTap: () => _exec(<String>["shell", "input", "keyevent", "3"], success: "Home"),
      ),
      _ActionTile(
        icon: Icons.crop_square_rounded,
        label: "Recents",
        onTap: () => _exec(<String>["shell", "input", "keyevent", "187"], success: "Recents"),
      ),
    ];
    return _buildGrid(tiles, columns: 3);
  }

  Widget _buildGrid(List<Widget> tiles, {required int columns}) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double gap = 8;
        final double tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: tiles.map((Widget tile) => SizedBox(width: tileWidth, child: tile)).toList(growable: false),
        );
      },
    );
  }

  Widget _buildDeepLinkCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _deepLinkController,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: "https://example.com or app://path",
                hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _launchSystemDeepLink(),
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(icon: Icons.open_in_new_rounded, label: "Open", onTap: _launchSystemDeepLink),
        ],
      ),
    );
  }

  Widget _buildPackagesEntry() {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        setState(() => _view = _AdbView.packages);
        if (_packages == null) unawaited(_loadPackages());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Design.accent.withAlpha(30)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.inventory_2_outlined, size: 16, color: Design.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Installed Packages",
                style: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w700, color: Design.text),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Design.text.withAlpha(140)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Packages view
  // -------------------------------------------------------------------------

  Widget _buildPackagesView() {
    if (_loadingPackages && _packages == null) {
      return Center(
        child: Text(
          "Loading packages...",
          style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(150)),
        ),
      );
    }
    final List<_AdbPackage> all = _packages ?? <_AdbPackage>[];
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _selectedSerial == null ? "Connect a device first." : "No third-party packages found.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(150)),
          ),
        ),
      );
    }

    final String query = _searchController.text.trim().toLowerCase();
    final List<_AdbPackage> filtered = query.isEmpty
        ? all
        : all.where((_AdbPackage p) => p.name.toLowerCase().contains(query)).toList(growable: false);
    final List<_AdbPackage> favorites = filtered.where((_AdbPackage p) => p.favorite).toList(growable: false);
    final List<_AdbPackage> others = filtered.where((_AdbPackage p) => !p.favorite).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: TextField(
            controller: _searchController,
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
            decoration: InputDecoration(
              isDense: true,
              hintText: "Search packages...",
              hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
              prefixIcon: Icon(Icons.search_rounded, size: 16, color: Design.accent),
              filled: true,
              fillColor: Design.accent.withAlpha(12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Design.accent.withAlpha(90), width: 1),
              ),
            ),
          ),
        ),
        Flexible(
          child: WindowsScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (favorites.isNotEmpty) ...<Widget>[
                  _buildSectionLabel(label: "Favorites", icon: Icons.star_rounded, count: favorites.length),
                  const SizedBox(height: 6),
                  ...favorites.map(_buildPackageRow),
                  const SizedBox(height: 10),
                  _buildSectionLabel(label: "All", icon: Icons.apps_rounded, count: others.length),
                  const SizedBox(height: 6),
                ],
                ...others.map(_buildPackageRow),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPackageRow(_AdbPackage package) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      hoverColor: Design.accent.withAlpha(14),
      onTap: () => setState(() {
        _activePackage = package.name;
        _packageDeepLinkController.clear();
        _showPackageDeepLink = false;
        _view = _AdbView.packageActions;
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: <Widget>[
            Icon(Icons.android, size: 15, color: Design.text.withAlpha(150)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                package.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => _toggleFavorite(package.name),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  package.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 16,
                  color: package.favorite ? Design.accent : Design.text.withAlpha(110),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Package actions view
  // -------------------------------------------------------------------------

  Widget _buildPackageActionsView() {
    final String pkg = _activePackage ?? "";
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildActionRow(
              icon: Icons.play_arrow_rounded, title: "Launch", subtitle: "am start", onTap: () => _launchPackage(pkg)),
          _buildActionRow(
              icon: Icons.refresh_rounded,
              title: "Restart",
              subtitle: "force-stop + start",
              onTap: () => _restartPackage(pkg)),
          _buildActionRow(
            icon: Icons.stop_circle_outlined,
            title: "Kill Process",
            subtitle: "am kill (background only)",
            onTap: () => _exec(<String>["shell", "am", "kill", pkg], success: "Killed $pkg"),
          ),
          _buildActionRow(
            icon: Icons.do_not_disturb_on_outlined,
            title: "Force Stop",
            subtitle: "am force-stop",
            onTap: () => _exec(<String>["shell", "am", "force-stop", pkg], success: "Force stopped $pkg"),
          ),
          _buildActionRow(
            icon: Icons.cleaning_services_rounded,
            title: "Clear App Data",
            subtitle: "pm clear",
            onTap: () => _exec(<String>["shell", "pm", "clear", pkg], success: "Cleared data for $pkg"),
          ),
          _buildActionRow(
              icon: Icons.restore_page_rounded,
              title: "Clear Data & Restart",
              subtitle: "pm clear + start",
              onTap: () => _clearAndRestart(pkg)),
          _buildActionRow(
              icon: Icons.verified_user_outlined,
              title: "Grant All Permissions",
              subtitle: "pm grant",
              onTap: () => _changePermissions(pkg, grant: true)),
          _buildActionRow(
              icon: Icons.block_rounded,
              title: "Revoke All Permissions",
              subtitle: "pm revoke",
              onTap: () => _changePermissions(pkg, grant: false)),
          _buildActionRow(
            icon: Icons.link_rounded,
            title: "Open Deep Link",
            subtitle: "am start -p $pkg",
            onTap: () => setState(() => _showPackageDeepLink = !_showPackageDeepLink),
            trailing: Icon(_showPackageDeepLink ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 16, color: Design.text.withAlpha(140)),
          ),
          if (_showPackageDeepLink) _buildPackageDeepLinkField(pkg),
          const SizedBox(height: 6),
          _buildActionRow(
              icon: Icons.delete_outline_rounded,
              title: "Uninstall",
              subtitle: "pm uninstall",
              danger: true,
              onTap: () => _confirmUninstall(pkg)),
        ],
      ),
    );
  }

  Widget _buildPackageDeepLinkField(String pkg) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.accent.withAlpha(30)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _packageDeepLinkController,
              autofocus: true,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
              decoration: InputDecoration(
                isDense: true,
                hintText: "app://path",
                hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _launchPackageDeepLink(pkg),
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(icon: Icons.open_in_new_rounded, label: "Open", onTap: () => _launchPackageDeepLink(pkg)),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
    Widget? trailing,
  }) {
    final Color tint = danger ? Colors.redAccent : Design.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: tint.withAlpha(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: danger ? Colors.redAccent.withAlpha(10) : Design.text.withAlpha(7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: danger ? Colors.redAccent.withAlpha(40) : Design.text.withAlpha(16)),
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        fontWeight: FontWeight.w600,
                        color: danger ? Colors.redAccent : Design.text,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(130)),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Settings view
  // -------------------------------------------------------------------------

  Widget _buildSettingsView() {
    return WindowsScrollView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSettingCard(
            title: "ADB executable",
            description: "Leave empty to use 'adb' from PATH.",
            controller: _adbPathController,
            hint: "adb",
            settingKey: _AdbService.adbPathKey,
            onPick: () => _pickAdbExe(),
            pickIcon: Icons.folder_open_rounded,
          ),
          const SizedBox(height: 8),
          _buildSettingCard(
            title: "Screenshot folder",
            description: "Where pulled screenshots are saved. Empty uses Pictures.",
            controller: _screenshotFolderController,
            hint: "%USERPROFILE%\\Pictures",
            settingKey: _AdbService.screenshotFolderKey,
            onPick: () =>
                _pickFolder(_screenshotFolderController, _AdbService.screenshotFolderKey, "Select screenshot folder"),
            pickIcon: Icons.folder_open_rounded,
          ),
          const SizedBox(height: 8),
          _buildSettingCard(
            title: "APK folder",
            description: "Default folder the APK picker opens in.",
            controller: _apkFolderController,
            hint: "%USERPROFILE%\\Downloads",
            settingKey: _AdbService.apkFolderKey,
            onPick: () => _pickFolder(_apkFolderController, _AdbService.apkFolderKey, "Select APK folder"),
            pickIcon: Icons.folder_open_rounded,
          ),
          const SizedBox(height: 8),
          _buildToggleSettingCard(
            title: "Skip uninstall confirmation",
            description: "Uninstall immediately without a confirmation dialog.",
            value: _skipUninstallConfirm,
            onChanged: (bool value) {
              setState(() {});
              Boxes.updateSettings(_AdbService.skipUninstallKey, value);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _pickAdbExe() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{"adb.exe": "adb.exe", "All files (*.*)": "*.*"}
      ..defaultFilterIndex = 0
      ..title = "Select adb.exe";
    final File? file = picker.getFile();
    Timer(const Duration(milliseconds: 400), () => QuickMenuFunctions.keepOpen = false);
    if (file == null) return;
    setState(() => _adbPathController.text = file.path);
    Boxes.updateSettings(_AdbService.adbPathKey, file.path);
  }

  Widget _buildSettingCard({
    required String title,
    required String description,
    required TextEditingController controller,
    required String hint,
    required String settingKey,
    required VoidCallback onPick,
    required IconData pickIcon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.text)),
          const SizedBox(height: 2),
          Text(description, style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
                    filled: true,
                    fillColor: Design.text.withAlpha(8),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Design.accent.withAlpha(90), width: 1),
                    ),
                  ),
                  onChanged: (String value) => Boxes.updateSettings(settingKey, value.trim()),
                ),
              ),
              const SizedBox(width: 8),
              _SmallButton(icon: pickIcon, label: "Browse", onTap: onPick),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSettingCard({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style:
                        TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.text)),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MiniToggleSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  Widget _buildSectionLabel({required String label, required IconData icon, int? count}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        if (count != null) ...<Widget>[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(99)),
            child: Text("$count", style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles & buttons
// ---------------------------------------------------------------------------

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool on = value ?? false;
    final String state = value == null ? "—" : (on ? "ON" : "OFF");
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      hoverColor: Design.accent.withAlpha(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: on ? Design.accent.withAlpha(28) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Icon(icon, size: 16, color: on ? Design.accent : Design.text.withAlpha(160)),
                Text(
                  state,
                  style: TextStyle(
                    fontSize: Design.baseFontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: on ? Design.accent : Design.text.withAlpha(120),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.w600,
                color: Design.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      hoverColor: Design.accent.withAlpha(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        decoration: BoxDecoration(
          color: Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Design.text.withAlpha(16)),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 18, color: Design.accent),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w600, color: Design.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Design.accent.withAlpha(70), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: Design.accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: Design.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
