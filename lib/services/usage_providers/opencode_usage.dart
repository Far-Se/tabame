import 'dart:convert';
import 'dart:io';

import '../provider_usage_service.dart';

/// OpenCode Go subscription meters, ported from Claude-Code-Usage-Monitor.
///
/// OpenCode keeps no reusable login on disk, so the dashboard workspace id
/// and auth cookie come from `OPENCODE_GO_WORKSPACE_ID` +
/// `OPENCODE_GO_AUTH_COOKIE`, or from a JSON file
/// (`{"workspaceId": "...", "authCookie": "..."}`) at
/// `%APPDATA%\opencode-go\config.json` (or `OPENCODE_GO_CONFIG_FILE`,
/// `~/.config/opencode-bar/opencode-go.json`, `~/.config/opencode-quota/opencode-go.json`).
class OpenCodeUsageFetcher extends ProviderUsageFetcher {
  static const String _statusUrl = 'https://opencode.ai/console/api/go/status';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  @override
  Future<ProviderUsageRecord> fetch() async {
    final _OpenCodeCredentials? credentials = _readCredentials();
    if (credentials == null) {
      throw const UsageFetchException('Add {"workspaceId","authCookie"} to %APPDATA%\\opencode-go\\config.json '
          'to make OpenCode Go usage available.');
    }

    final String cookie = credentials.authCookie.split(';').any((String part) {
      final String p = part.trimLeft();
      return p.startsWith('auth=') || p.startsWith('__Host-console_session=');
    })
        ? credentials.authCookie
        : 'auth=${credentials.authCookie}';

    final UsageHttpResult result = await usageJsonRequest('GET', _statusUrl, headers: <String, String>{
      'x-org-id': credentials.workspaceId,
      'Cookie': cookie,
      'User-Agent': _userAgent,
    });
    if (result.isAuthError) throw const UsageFetchException('OpenCode Go cookie expired. Copy a fresh auth cookie.');
    if (!result.ok) {
      throw UsageFetchException(result.status == null
          ? 'Could not reach OpenCode.'
          : 'OpenCode Go usage is temporarily unavailable (HTTP ${result.status}).');
    }

    final dynamic access = result.body is Map ? (result.body as Map<dynamic, dynamic>)['access'] : null;
    if (access is! Map || access['meters'] is! Map) {
      throw const UsageFetchException('No active OpenCode Go subscription found.');
    }
    final Map<dynamic, dynamic> meters = access['meters'] as Map<dynamic, dynamic>;
    final List<ProviderUsageWindow> windows = <ProviderUsageWindow>[
      if (_window('5-hour limit', meters['fiveHour'], null) case final ProviderUsageWindow w) w,
      if (_window('Weekly limit', meters['week'], null) case final ProviderUsageWindow w) w,
      if (_window('Monthly limit', meters['month'], access['endsAt']) case final ProviderUsageWindow w) w,
    ];
    if (windows.isEmpty) throw const UsageFetchException('OpenCode Go returned no usage windows.');
    return ProviderUsageRecord(windows: windows, fetchedAt: DateTime.now());
  }

  /// Amounts are microcents serialized as strings (JavaScript BigInts).
  static ProviderUsageWindow? _window(String label, dynamic meter, dynamic fallbackReset) {
    if (meter is! Map) return null;
    final BigInt? limit = BigInt.tryParse((meter['limitMicroCents'] ?? '').toString());
    final BigInt? used = BigInt.tryParse((meter['usedMicroCents'] ?? '').toString());
    if (limit == null || used == null) return null;
    final double percent = limit == BigInt.zero ? 0 : used.toDouble() / limit.toDouble() * 100;
    return ProviderUsageWindow(
      label: label,
      usedPercent: percent.clamp(0, 100).toDouble(),
      // An unused rolling window has no reset time until the first request.
      resetAt: parseUsageDate(meter['resetsAt'] ?? fallbackReset),
    );
  }

  static bool _validWorkspace(String value) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value);
  static bool _validCookie(String value) => value.isNotEmpty && !value.contains('\n') && !value.contains('\r');

  _OpenCodeCredentials? _readCredentials() {
    final String? envWorkspace = nonEmptyEnvironment('OPENCODE_GO_WORKSPACE_ID');
    final String? envCookie = nonEmptyEnvironment('OPENCODE_GO_AUTH_COOKIE');
    if (envWorkspace != null && envCookie != null && _validWorkspace(envWorkspace) && _validCookie(envCookie)) {
      return _OpenCodeCredentials(envWorkspace, envCookie);
    }

    final String home = usageHomeDirectory;
    final String? appData = nonEmptyEnvironment('APPDATA');
    final String? xdg = nonEmptyEnvironment('XDG_CONFIG_HOME');
    final List<String> paths = <String>[
      if (nonEmptyEnvironment('OPENCODE_GO_CONFIG_FILE') case final String path) path,
      if (appData != null) '$appData\\opencode-go\\config.json',
      if (xdg != null) ...<String>['$xdg\\opencode-bar\\opencode-go.json', '$xdg\\opencode-quota\\opencode-go.json'],
      if (home.isNotEmpty) ...<String>[
        '$home\\.config\\opencode-bar\\opencode-go.json',
        '$home\\.config\\opencode-quota\\opencode-go.json',
      ],
    ];
    for (final String path in paths) {
      try {
        final File file = File(path);
        if (!file.existsSync()) continue;
        final dynamic config = jsonDecode(file.readAsStringSync());
        if (config is! Map) continue;
        final String workspace =
            (config['workspace_id'] ?? config['workspaceId'] ?? config['workspaceID'] ?? '').toString().trim();
        final String cookie = (config['auth_cookie'] ?? config['authCookie'] ?? config['cookie'] ?? '').toString().trim();
        if (_validWorkspace(workspace) && _validCookie(cookie)) return _OpenCodeCredentials(workspace, cookie);
      } on Object {
        // Try the next location.
      }
    }
    return null;
  }
}

class _OpenCodeCredentials {
  const _OpenCodeCredentials(this.workspaceId, this.authCookie);

  final String workspaceId;
  final String authCookie;
}
