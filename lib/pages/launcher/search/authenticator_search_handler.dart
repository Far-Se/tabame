import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/authenticator_entry.dart';
import '../../../models/classes/authenticator_manager.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../widgets/itzy/quickmenu/button_authenticator.dart' show AuthenticatorLogoStore;
import '../../../widgets/itzy/quickmenu/button_quickactions.dart';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';

class AuthenticatorSearchHandler {
  AuthenticatorSearchHandler._(this.context);

  final LauncherSearchContext context;
  final Map<(String, String), Future<Uint8List?>> _logoFutures = <(String, String), Future<Uint8List?>>{};
  bool _copying = false;
  bool _finished = false;

  bool get _active =>
      !context.isDisposed &&
      !_finished &&
      QuickMenuFunctions.isQuickMenuVisible &&
      context.isActiveSearch(context.requestId, context.query);

  static void handle(LauncherSearchContext context) {
    unawaited(AuthenticatorSearchHandler._(context)._refresh());
  }

  Future<void> _refresh() async {
    if (!_active) return;
    try {
      // Without a password, the manager opens device-protected and legacy
      // default-password storage, but refuses accounts requiring a custom password.
      final List<AuthenticatorEntry> entries = await AuthenticatorManager.loadEntries();
      if (!_active) return;
      final String filter = context.lowerQuery.trim();
      final List<LauncherSearchResultItem> results = <LauncherSearchResultItem>[];
      final DateTime now = DateTime.now();
      for (final AuthenticatorEntry entry in entries) {
        if (!'${entry.issuer} ${entry.accountName}'.toLowerCase().contains(filter)) continue;
        try {
          final String code = AuthenticatorManager.generateCode(entry, now: now);
          final int remaining = AuthenticatorManager.secondsRemaining(entry, now: now);
          final String title = '${entry.title} · ${entry.subtitle} · $code · ${remaining}s';
          results.add(LauncherSearchResultItem.quickAction(QuickActionMenuEntry(
            id: 'auth:${entry.id}',
            title: title,
            searchTerms: <String>[entry.issuer, entry.accountName],
            iconBuilder: (BuildContext context) => _buildLogo(context, entry),
            onExecute: () => unawaited(_copy(entry.id)),
            builder: (BuildContext context) => ListTile(
              dense: true,
              leading: _buildLogo(context, entry),
              title: Text(title),
              subtitle: const Text('Copy code'),
              onTap: () => unawaited(_copy(entry.id)),
            ),
          )));
        } catch (_) {
          results.add(
              _info('invalid:${entry.id}', entry.title, 'Unable to generate this code. Check it in Authenticator.'));
        }
      }
      context.setResults(
        results.isNotEmpty
            ? results
            : <LauncherSearchResultItem>[
                _info('empty', entries.isEmpty ? 'No authenticator accounts' : 'No matching accounts',
                    entries.isEmpty ? 'Add accounts in the Authenticator panel.' : 'Search by issuer or account name.'),
              ],
        resetSelection: false,
      );
      // A one-shot timer avoids overlapping reads. Stale searches stop here.
      Timer(const Duration(seconds: 1), () => unawaited(_refresh()));
    } on FormatException {
      if (_active)
        context.setResults(<LauncherSearchResultItem>[
          _info('unavailable', 'Authenticator unavailable',
              'Open the Authenticator panel to unlock password-protected accounts or check the storage file.')
        ]);
    } catch (_) {
      if (_active)
        context.setResults(<LauncherSearchResultItem>[
          _info('error', 'Unable to load codes', 'Open the Authenticator panel to check your accounts.')
        ]);
    }
  }

  Widget _buildLogo(BuildContext context, AuthenticatorEntry entry) {
    // Keep the future stable across the one-second code refreshes.
    final Future<Uint8List?> future = _logoFutures.putIfAbsent(
      (entry.issuer, entry.accountName),
      () => AuthenticatorLogoStore.instance.getLogo(entry),
    );
    final Widget fallback = Center(
      child: Text(
        entry.title.characters.first.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
      ),
    );
    return SizedBox.square(
      dimension: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FutureBuilder<Uint8List?>(
          future: future,
          builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
            final Uint8List? bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) return fallback;
            return Image.memory(
              bytes,
              width: 24,
              height: 24,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => fallback,
            );
          },
        ),
      ),
    );
  }

  Future<void> _copy(String id) async {
    if (!_active || _copying) return;
    _copying = true;
    try {
      // Re-read without a password so setting a custom password or deleting an
      // account takes effect before copying.
      final List<AuthenticatorEntry> entries = await AuthenticatorManager.loadEntries();
      if (!_active) return;
      final AuthenticatorEntry entry = entries.firstWhere((AuthenticatorEntry entry) => entry.id == id);
      await Clipboard.setData(ClipboardData(text: AuthenticatorManager.generateCode(entry)));
      if (!_active) return;
      _finished = true;
      context.setResults(<LauncherSearchResultItem>[]);
      user.launcherSearchText = '';
      await QuickMenuFunctions.hideQuickMenu();
    } catch (_) {
      if (_active)
        context.setResults(<LauncherSearchResultItem>[
          _info('copy-error', 'Unable to copy code', 'Search again or open the Authenticator panel.')
        ]);
    } finally {
      _copying = false;
    }
  }

  static LauncherSearchResultItem _info(String id, String title, String subtitle) =>
      LauncherSearchResultItem.info(LauncherInfoResult(
        id: 'auth:$id',
        title: title,
        subtitle: subtitle,
        icon: Icons.password_rounded,
      ));
}
