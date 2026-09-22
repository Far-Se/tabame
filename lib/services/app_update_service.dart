import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../logic/error_handler.dart';
import '../models/globals.dart';
import '../platform/app_paths.dart';

/// Downloads are independent of installation. Only a normal, fresh Windows
/// launch can hand a verified package to the external replacement helper.
abstract final class AppUpdateService {
  static const String _repository = 'https://api.github.com/repos/Far-Se/tabame';
  static const Duration _checkInterval = Duration(hours: 6);
  static const Duration _retryInterval = Duration(hours: 1);
  static final ValueNotifier<String> status = ValueNotifier<String>('Check for updates');
  static Timer? _timer;
  static Future<bool>? _inFlight;
  static bool _versionReady = false;
  static String? availableVersion;

  static String get _installDirectory => File(Platform.resolvedExecutable).parent.path;
  static String get _directory {
    final String identity = sha256.convert(utf8.encode(_installDirectory.toLowerCase())).toString().substring(0, 16);
    return AppPaths.currentPath(p.join('updates', identity));
  }

  static File _file(String name) => File(p.join(_directory, name));

  static bool get supported =>
      _versionReady &&
      Platform.isWindows &&
      kReleaseMode &&
      p.basename(Platform.resolvedExecutable).toLowerCase() == 'tabame.exe' &&
      !File(p.join(_installDirectory, 'AppxManifest.xml')).existsSync();

  static Future<void> initialize() async {
    try {
      await _initialize();
    } catch (error, stack) {
      _versionReady = false;
      status.value = 'The updater is unavailable. You can download releases from GitHub.';
      await ErrorLogger.log('UpdateInitialization', error.toString(), stack);
    }
  }

  static Future<void> _initialize() async {
    // The bundled pubspec is the version authority, including local builds.
    final String spec = await rootBundle.loadString('pubspec.yaml');
    final String? version = RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(spec)?.group(1);
    if (version == null || _version(version) == null) throw const FormatException('Invalid packaged app version.');
    Globals.version = 'v$version';
    _versionReady = true;
    if (!supported) {
      //TODO: Implement multiplatform
      status.value = 'Use your platform installer to update Tabame.';
      return;
    }
    await Directory(_directory).create(recursive: true);
    final Map<String, dynamic>? pending = await _readJson('pending.json');
    if (pending != null && _newer(pending['version'] as String, Globals.version)) {
      availableVersion = pending['version'] as String;
      status.value = '$availableVersion is ready for the next app launch.';
    }
    final Map<String, dynamic>? result = await _readJson('result.json');
    if (pending == null && result?['success'] == false) {
      status.value = 'The last update could not be installed. See the update log or check again.';
    }
  }

  /// Runs in the main quick-menu process. Persisted throttling also covers
  /// restarts, multiple processes and settings changes in the interface process.
  static void start() {
    if (!supported || _timer != null) return;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_automaticCheck()));
    unawaited(_automaticCheck());
  }

  static Future<bool> _automaticEnabled() async {
    try {
      final dynamic settings = jsonDecode(await File(AppPaths.settingsPath('settings.json')).readAsString());
      return (settings['flutter.autoUpdate'] ?? settings['autoUpdate']) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _automaticCheck() async {
    if (await _automaticEnabled()) await check(background: true);
  }

  /// Manual checks also stage the release; neither mode interrupts active work.
  static Future<bool> check({bool background = false}) {
    return _inFlight ??= _check(background: background).whenComplete(() => _inFlight = null);
  }

  static Future<bool> _check({required bool background}) async {
    if (!supported) return false;
    RandomAccessFile? lock;
    final http.Client client = http.Client();
    try {
      lock = await _tryLock();
      if (lock == null) {
        if (!background) status.value = 'Another Tabame process is preparing an update.';
        return false;
      }
      if (await _file('journal.json').exists()) {
        status.value = 'An interrupted update needs recovery. Close Tabame and launch it again.';
        return false;
      }
      final Map<String, dynamic>? schedule = await _readJson('schedule.json');
      if (background && DateTime.now().millisecondsSinceEpoch < (schedule?['nextCheck'] as int? ?? 0)) return false;
      await _schedule(_retryInterval);
      status.value = 'Checking for updates…';
      final http.Response response =
          await client.get(Uri.parse('$_repository/releases/latest'), headers: <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Tabame-Updater',
        'X-GitHub-Api-Version': '2022-11-28',
      }).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw HttpException('Release check returned HTTP ${response.statusCode}.');
      final Map<String, dynamic> release = jsonDecode(response.body) as Map<String, dynamic>;
      final String version = release['tag_name'] as String;
      if (release['draft'] != false || release['prerelease'] != false || _version(version) == null) {
        throw const FormatException('The stable release has an invalid version.');
      }
      if (!_newer(version, Globals.version)) {
        availableVersion = null;
        status.value = 'You have the latest version.';
        await _schedule(_checkInterval);
        return false;
      }
      final List<Map<String, dynamic>> assets = (release['assets'] as List<dynamic>).cast<Map<String, dynamic>>();
      final String name = 'tabame-$version-windows.zip';
      final Map<String, dynamic> asset = assets.singleWhere((Map<String, dynamic> value) => value['name'] == name);
      final Map<String, dynamic> checksum =
          assets.singleWhere((Map<String, dynamic> value) => value['name'] == '$name.sha256');
      final http.Response hashResponse = await client.get(_assetUri(checksum)).timeout(const Duration(seconds: 30));
      if (hashResponse.statusCode != 200) throw const HttpException('Could not download the release checksum.');
      final List<String> hashParts = hashResponse.body.trim().split(RegExp(r'\s+'));
      if (hashParts.length != 2 || hashParts[1] != name || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hashParts[0])) {
        throw const FormatException('Invalid release checksum.');
      }
      final String hash = hashParts[0].toLowerCase();
      final String? digest = asset['digest'] as String?;
      if (digest != null && digest != 'sha256:$hash') throw const FormatException('Release digests disagree.');
      final Map<String, dynamic>? lastResult = await _readJson('result.json');
      if (background && lastResult?['success'] == false && lastResult?['sha256'] == hash) {
        status.value = 'Automatic retry paused for $version. Check again to retry manually.';
        await _schedule(_checkInterval);
        return false;
      }
      final Map<String, dynamic>? pending = await _readJson('pending.json');
      if (pending?['sha256'] != hash || !await _validArchive(hash)) {
        status.value = 'Downloading $version in the background…';
        final File partial = _file('package.part');
        final http.StreamedResponse download =
            await client.send(http.Request('GET', _assetUri(asset))).timeout(const Duration(seconds: 30));
        if (download.statusCode != 200) throw HttpException('Download returned HTTP ${download.statusCode}.');
        final int expectedSize = asset['size'] as int;
        if (expectedSize <= 0 || expectedSize > 1024 * 1024 * 1024)
          throw const FormatException('Invalid package size.');
        int received = 0;
        final IOSink sink = partial.openWrite();
        try {
          await sink.addStream(download.stream.timeout(const Duration(seconds: 60)).map((List<int> chunk) {
            received += chunk.length;
            if (received > expectedSize) throw const FormatException('Package exceeds its declared size.');
            return chunk;
          }));
        } finally {
          await sink.close();
        }
        if (received != expectedSize || (await sha256.bind(partial.openRead()).first).toString() != hash) {
          throw const FormatException('Package verification failed.');
        }
        // Do not arm an automatic install if the preference changed mid-download.
        if (background && !await _automaticEnabled()) {
          status.value = 'Automatic updates are off.';
          return false;
        }
        final File archive = _file('package.zip');
        if (await archive.exists()) await archive.delete();
        await partial.rename(archive.path);
      }
      await _writeJson('pending.json', <String, dynamic>{
        'schema': 1,
        'version': version,
        'sha256': hash,
        'installDirectory': _installDirectory,
        'automatic': background && !(pending?['sha256'] == hash && pending?['automatic'] == false),
      });
      availableVersion = version;
      status.value = '$version is ready for the next app launch.';
      await _schedule(_checkInterval);
      return true;
    } catch (error, stack) {
      status.value = 'Could not prepare the update. Your current version is unchanged; try again later.';
      await ErrorLogger.log('AppUpdateService', error.toString(), stack);
      return false;
    } finally {
      client.close();
      if (lock != null) await lock.close();
    }
  }

  static Uri _assetUri(Map<String, dynamic> asset) {
    final Uri uri = Uri.parse(asset['browser_download_url'] as String);
    if (uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        !uri.path.toLowerCase().startsWith('/far-se/tabame/releases/download/')) {
      throw const FormatException('Unexpected release asset URL.');
    }
    return uri;
  }

  static Future<bool> _validArchive(String hash) async {
    final File archive = _file('package.zip');
    return await archive.exists() && (await sha256.bind(archive.openRead()).first).toString() == hash;
  }

  /// Called before the window and hooks are initialized, so no user work is lost.
  /// The helper acknowledges ownership before this process is allowed to exit.
  static Future<void> applyOnLaunch(List<String> arguments) async {
    if (!supported || arguments.any((String arg) => arg != '-tryadmin' && arg != '-restarted')) return;
    try {
      final Map<String, dynamic>? pending = await _readJson('pending.json');
      final bool recovering = await _file('journal.json').exists();
      if (pending == null ||
          pending['schema'] != 1 ||
          (!recovering && !_newer(pending['version'] as String, Globals.version))) return;
      if (!recovering && pending['automatic'] == true && !await _automaticEnabled()) return;
      final String token = '${DateTime.now().microsecondsSinceEpoch}-$pid';
      final File script = _file('apply-$token.ps1');
      await script.writeAsString(await rootBundle.loadString('resources/updater/apply-update.ps1'), flush: true);
      final String powershell = p.join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32',
          'WindowsPowerShell', 'v1.0', 'powershell.exe');
      await Process.start(
          powershell,
          <String>[
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-WindowStyle',
            'Hidden',
            '-File',
            script.path,
            '-UpdateRoot',
            _directory,
            '-InstallRoot',
            _installDirectory,
            '-ParentId',
            '$pid',
            '-Token',
            token,
          ],
          mode: ProcessStartMode.detached);
      final File ready = _file('ready-$token');
      for (int attempt = 0; attempt < 100; attempt++) {
        if (await ready.exists()) exit(0);
        if (await _file('done-$token').exists()) {
          await _file('done-$token').delete();
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // The helper also has a timeout; a failed handoff never blocks startup.
    } catch (error, stack) {
      await ErrorLogger.log('UpdateHandoff', error.toString(), stack);
    }
  }

  static Future<void> acknowledgeLaunch(List<String> arguments) async {
    if (!supported) return;
    for (final String arg in arguments) {
      if (arg.startsWith('-update-token=')) {
        final String token = arg.substring('-update-token='.length);
        if (RegExp(r'^\d+-\d+$').hasMatch(token)) {
          await _file('healthy-$token').writeAsString(Globals.version, flush: true);
        }
      }
    }
  }

  static Future<RandomAccessFile?> _tryLock() async {
    final RandomAccessFile file = await _file('update.lock').open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
      return file;
    } on FileSystemException {
      await file.close();
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _readJson(String name) async {
    try {
      return jsonDecode(await _file(name).readAsString()) as Map<String, dynamic>;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<void> _writeJson(String name, Map<String, dynamic> value) async {
    final File temporary = _file('$name.tmp');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(_file(name).path);
  }

  static Future<void> _schedule(Duration delay) => _writeJson('schedule.json', <String, dynamic>{
        'nextCheck': DateTime.now().add(delay).millisecondsSinceEpoch,
      });

  static List<int>? _version(String value) {
    final RegExpMatch? match = RegExp(r'^v?(\d+)\.(\d+)(?:\.(\d+))?(?:\+\d+)?$').firstMatch(value);
    return match == null ? null : <int>[int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3] ?? '0')];
  }

  static bool _newer(String candidate, String installed) {
    final List<int>? a = _version(candidate);
    final List<int>? b = _version(installed);
    if (a == null || b == null) return false;
    for (int index = 0; index < 3; index++) {
      if (a[index] != b[index]) return a[index] > b[index];
    }
    return false;
  }
}
