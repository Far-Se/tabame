import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/authenticator_entry.dart';
import '../../../models/classes/authenticator_manager.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/qr_capture_decoder.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class AuthenticatorButton extends StatelessWidget {
  const AuthenticatorButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Authenticator", icon: const Icon(Icons.shield_outlined), child: () => const AuthenticatorPanel());
  }
}

class AuthenticatorPanel extends StatefulWidget {
  const AuthenticatorPanel({super.key});

  @override
  State<AuthenticatorPanel> createState() => _AuthenticatorPanelState();
}

class _AuthenticatorPanelState extends State<AuthenticatorPanel> {
  final TextEditingController _uriController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<String, GlobalKey<_AuthenticatorTileState>> _tileKeys = <String, GlobalKey<_AuthenticatorTileState>>{};

  List<AuthenticatorEntry> _entries = <AuthenticatorEntry>[];
  bool _loading = true;
  bool _adding = false;
  bool _busy = false;
  bool _copiedExport = false;
  bool _isEncrypted = false;
  String? _activePassword;
  String? _errorMessage;
  String? _infoMessage;
  DateTime _now = DateTime.now();
  Timer? _ticker;
  Timer? _infoMessageTimer;
  Timer? _copiedExportTimer;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _infoMessageTimer?.cancel();
    _copiedExportTimer?.cancel();
    _uriController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final AuthenticatorStorageInfo storageInfo = await AuthenticatorManager.getStorageInfo();
    String? password;

    try {
      if (storageInfo.isEncrypted) {
        if (storageInfo.requiresPasswordPrompt) {
          password = await _promptForPassword(
            title: 'Unlock Authenticator',
            confirmLabel: 'Unlock',
            message: 'This authenticator is encrypted. Enter the password to continue.',
            emptyUsesDefault: false,
            allowEmpty: false,
          );
          if (password == null) {
            if (!mounted) return;
            setState(() {
              _entries = <AuthenticatorEntry>[];
              _isEncrypted = true;
              _activePassword = null;
              _loading = false;
              _errorMessage = 'Authenticator remains locked until you enter the password.';
            });
            return;
          }
        } else {
          password = AuthenticatorManager.defaultEncryptionPassword;
        }
      }

      final List<AuthenticatorEntry> entries = await AuthenticatorManager.loadEntries(password: password);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isEncrypted = storageInfo.isEncrypted;
        _activePassword = storageInfo.isEncrypted ? password : null;
        _loading = false;
        _errorMessage = null;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = <AuthenticatorEntry>[];
        _isEncrypted = storageInfo.isEncrypted;
        _activePassword = null;
        _loading = false;
        _errorMessage = e.message;
      });
    }
  }

  Future<void> _saveUriInput() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      await _importRawContent(_uriController.text, sourceLabel: 'input');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is FormatException ? e.message : 'Unable to add the authenticator from the provided input.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _captureQrCode() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = 'Capture the QR code on screen.';
    });

    try {
      QuickMenuFunctions.keepOpen = true;
      await WinUtils.screenCapture();

      Timer(const Duration(milliseconds: 1000), () async {
        QuickMenuFunctions.keepOpen = false;
      });
      final String capturePath = "${WinUtils.getTempFolder()}\\capture.png";
      final File captureFile = File(capturePath);
      if (!captureFile.existsSync()) {
        throw const FormatException('No capture image was saved.');
      }

      final String? decoded = await compute<String, String?>(
        decodeQrValueFromCapturedPng,
        capturePath,
      );
      if (decoded == null || decoded.trim().isEmpty) {
        throw const FormatException('No QR code could be read from the capture.');
      }

      await _importRawContent(decoded, sourceLabel: 'QR capture');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is FormatException ? e.message : 'Unable to capture and scan the QR code.';
      });
    } finally {
      final String capturePath = "${WinUtils.getTempFolder()}\\capture.png";
      final File captureFile = File(capturePath);
      if (captureFile.existsSync()) {
        captureFile.deleteSync();
      }
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _importBackupFile() async {
    final OpenFilePicker filePicker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Text files (*.txt)': '*.txt',
        'All files (*.*)': '*.*',
      }
      ..defaultFilterIndex = 0
      ..title = 'Select authenticator backup file';

    final File? file = filePicker.getFile();
    if (file == null || !file.existsSync()) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = 'Importing backup file...';
    });

    try {
      final String content = await file.readAsString();
      await _importRawContent(content, sourceLabel: file.path.split(Platform.pathSeparator).last);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is FormatException ? e.message : 'Unable to read the selected backup file.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _importRawContent(String raw, {required String sourceLabel}) async {
    final List<String> uris = AuthenticatorManager.extractOtpAuthUris(raw);
    if (uris.isEmpty) {
      throw const FormatException('No valid otpauth:// or otpauth-migration:// entries were found.');
    }

    final int beforeCount = _entries.length;
    final List<AuthenticatorEntry> parsed = <AuthenticatorEntry>[];
    int invalidCount = 0;
    for (final String uri in uris) {
      try {
        parsed.add(AuthenticatorManager.parseOtpAuthUri(uri));
      } catch (_) {
        invalidCount++;
      }
    }

    if (parsed.isEmpty) {
      throw const FormatException('No valid authenticator entries could be parsed.');
    }

    final List<AuthenticatorEntry> updated = await AuthenticatorManager.mergeEntries(parsed, password: _activePassword);
    final int addedCount = updated.length - beforeCount;
    if (!mounted) return;

    final List<String> messageParts = <String>[];
    if (addedCount > 0) {
      messageParts.add(addedCount == 1 ? 'Added 1 authenticator.' : 'Added $addedCount authenticators.');
    } else {
      messageParts.add('All entries from $sourceLabel already exist.');
    }
    if (invalidCount > 0) {
      messageParts.add(
        invalidCount == 1 ? 'Skipped 1 invalid entry.' : 'Skipped $invalidCount invalid entries.',
      );
    }

    setState(() {
      _entries = updated;
      _adding = addedCount == 0;
      _uriController.clear();
      _errorMessage = null;
      _infoMessage = messageParts.join(' ');
    });
    _scheduleInfoMessageDismiss();
  }

  Future<void> _deleteEntry(AuthenticatorEntry entry) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Remove Authenticator?"),
          content: Text("Delete ${entry.title} from the authenticator list?"),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final List<AuthenticatorEntry> updated =
        await AuthenticatorManager.deleteEntry(entry.id, password: _activePassword);
    if (!mounted) return;
    setState(() {
      _entries = updated;
      _infoMessage = 'Removed ${entry.title}.';
    });
    _scheduleInfoMessageDismiss();
  }

  Future<void> _editEntry(AuthenticatorEntry entry) async {
    final TextEditingController issuerController = TextEditingController(text: entry.issuer);
    final TextEditingController accountController = TextEditingController(text: entry.accountName);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Edit Authenticator"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: issuerController,
                decoration: const InputDecoration(labelText: "Issuer (Site Name)"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: accountController,
                decoration: const InputDecoration(labelText: "Account Name (User)"),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final List<AuthenticatorEntry> current = await AuthenticatorManager.loadEntries(password: _activePassword);
    final int index = current.indexWhere((AuthenticatorEntry e) => e.id == entry.id);
    if (index >= 0) {
      current[index] = AuthenticatorEntry(
        id: entry.id,
        issuer: issuerController.text.trim(),
        accountName: accountController.text.trim(),
        secret: entry.secret,
        algorithm: entry.algorithm,
        digits: entry.digits,
        period: entry.period,
      );
      final List<AuthenticatorEntry> updated =
          await AuthenticatorManager.saveEntries(current, password: _activePassword);
      if (!mounted) return;
      setState(() {
        _entries = updated;
        _infoMessage = 'Updated ${current[index].title}.';
      });
      _scheduleInfoMessageDismiss();
    }
  }

  void _scheduleInfoMessageDismiss() {
    _infoMessageTimer?.cancel();
    _infoMessageTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _infoMessage == null) return;
      setState(() {
        _infoMessage = null;
      });
    });
  }

  Future<void> _copyAllEntries() async {
    if (_entries.isEmpty) return;

    final String export = _entries.map(AuthenticatorManager.buildOtpAuthUri).join('\n');
    await Clipboard.setData(ClipboardData(text: export));
    if (!mounted) return;

    _copiedExportTimer?.cancel();
    setState(() {
      _copiedExport = true;
      _infoMessage = 'Copied ${_entries.length} authenticator ${_entries.length == 1 ? 'entry' : 'entries'}.';
      _errorMessage = null;
    });
    _scheduleInfoMessageDismiss();
    _copiedExportTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _copiedExport = false);
    });
  }

  Future<void> _toggleEncryption() async {
    final String? password = await _promptForPassword(
      title: _isEncrypted ? 'Change Authenticator Password' : 'Encrypt Authenticator',
      confirmLabel: _isEncrypted ? 'Re-encrypt' : 'Encrypt',
      message: _isEncrypted
          ? 'Choose a new one-time password. The current encrypted file will be replaced.'
          : 'Choose a one-time password for the authenticator. You must remember it.',
      emptyUsesDefault: true,
      allowEmpty: true,
      confirmPassword: true,
    );
    if (password == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final bool wasEncrypted = _isEncrypted;
      await AuthenticatorManager.removeStorageFile();
      final String effectivePassword = password.isEmpty ? AuthenticatorManager.defaultEncryptionPassword : password;
      await AuthenticatorManager.encryptEntries(_entries, effectivePassword);
      if (!mounted) return;
      setState(() {
        _isEncrypted = true;
        _activePassword = effectivePassword;
        _infoMessage = password.isEmpty
            ? 'Authenticator encrypted with the default password.'
            : wasEncrypted
                ? 'Authenticator password updated.'
                : 'Authenticator encrypted.';
      });
      _scheduleInfoMessageDismiss();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to encrypt the authenticator right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<String?> _promptForPassword({
    required String title,
    required String confirmLabel,
    required String message,
    required bool emptyUsesDefault,
    required bool allowEmpty,
    bool confirmPassword = false,
  }) async {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return _AuthenticatorPasswordDialog(
          title: title,
          confirmLabel: confirmLabel,
          message: message,
          emptyUsesDefault: emptyUsesDefault,
          allowEmpty: allowEmpty,
          confirmPassword: confirmPassword,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: _adding ? "Add Authenticator" : "Authenticator",
          accent: accent,
          icon: _adding ? Icons.qr_code_2_rounded : Icons.shield_outlined,
          extraActions: <Widget>[
            CustomTooltip(
              message: "Encrypt",
              child: IconButton(
                onPressed: _busy ? null : _toggleEncryption,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(
                  _isEncrypted ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 14,
                  color: accent,
                ),
              ),
            ),
            if (_entries.isNotEmpty)
              CustomTooltip(
                message: "Copy All Entries",
                child: IconButton(
                  onPressed: _copyAllEntries,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  iconSize: 14,
                  icon: Icon(_copiedExport ? Icons.copy_rounded : Icons.archive, color: accent),
                ),
              ),
          ],
          buttonTooltip: "Add",
          buttonPressed: () {
            setState(() {
              _adding = !_adding;
              _errorMessage = null;
              _infoMessage = null;
            });
          },
          buttonIcon: _adding ? Icons.close : Icons.add,
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 1.5),
        if (_errorMessage != null)
          _StatusStrip(
            message: _errorMessage!,
            accent: Colors.redAccent,
            background: Colors.redAccent.withAlpha(24),
            onClose: () => setState(() => _errorMessage = null),
          ),
        if (_infoMessage != null)
          _StatusStrip(
            message: _infoMessage!,
            accent: accent,
            background: accent.withAlpha(16),
            onClose: () => setState(() => _infoMessage = null),
          ),
        Flexible(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _adding
                  ? _buildAddView(accent, onSurface)
                  : _buildCodesView(accent, onSurface),
        ),
      ],
    );
  }

  Widget _buildAddView(Color accent, Color onSurface) {
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildAddActionCard(
                    accent: accent,
                    onSurface: onSurface,
                    icon: Icons.screenshot_monitor_rounded,
                    title: "Capture QR Code",
                    subtitle: "Select an area on screen that contains a QR code and import it.",
                    onTap: _busy ? null : _captureQrCode,
                    highlighted: true,
                  ),
                  const SizedBox(height: 10),
                  _buildAddActionCard(
                    accent: accent,
                    onSurface: onSurface,
                    icon: Icons.upload_file_rounded,
                    title: "Import Backup File",
                    subtitle: "Read a text backup with one or more otpauth:// or otpauth-migration:// entries.",
                    onTap: _busy ? null : _importBackupFile,
                  ),
                  const SizedBox(height: 14),
                  _buildAddSectionLabel(
                    accent: accent,
                    onSurface: onSurface,
                    icon: Icons.link_rounded,
                    label: "Manual URI Import",
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: onSurface.withAlpha(8),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: onSurface.withAlpha(18)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextField(
                          controller: _uriController,
                          minLines: 3,
                          maxLines: 6,
                          decoration: InputDecoration(
                            hintText: 'otpauth://totp/Site:username?secret=SECRET&issuer=Site',
                            filled: true,
                            fillColor: accent.withAlpha(10),
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: accent.withAlpha(90)),
                            ),
                          ),
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 2,
                            color: onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _saveUriInput,
                          icon: const Icon(Icons.playlist_add_rounded, size: 16),
                          label: const Text("Add From URI"),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "logos by logo.dev",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      color: onSurface.withAlpha(135),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddSectionLabel({
    required Color accent,
    required Color onSurface,
    required IconData icon,
    required String label,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 15, color: accent),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: Design.baseFontSize + 2,
            fontWeight: FontWeight.w700,
            color: onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildAddActionCard({
    required Color accent,
    required Color onSurface,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool highlighted = false,
  }) {
    final Color background = highlighted ? accent.withAlpha(14) : onSurface.withAlpha(8);
    final Color border = highlighted ? accent.withAlpha(34) : onSurface.withAlpha(18);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withAlpha(highlighted ? 26 : 18),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        height: 1.35,
                        color: onSurface.withAlpha(165),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: onSurface.withAlpha(125),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodesView(Color accent, Color onSurface) {
    final String query = _searchController.text.trim().toLowerCase();
    final List<AuthenticatorEntry> visibleEntries = query.isEmpty
        ? _entries
        : _entries.where((AuthenticatorEntry entry) {
            final String issuer = entry.issuer.toLowerCase();
            final String account = entry.accountName.toLowerCase();
            final String title = entry.title.toLowerCase();
            final String subtitle = entry.subtitle.toLowerCase();
            return issuer.contains(query) ||
                account.contains(query) ||
                title.contains(query) ||
                subtitle.contains(query);
          }).toList(growable: false);

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.shield_outlined, size: 34, color: accent.withAlpha(140)),
              const SizedBox(height: 10),
              Text(
                "No authenticators yet",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Add one from an otpauth URI, an otpauth-migration payload, a backup file, or a captured QR code.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  color: onSurface.withAlpha(160),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => _adding = true),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text("Add Authenticator"),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      _copyFirstVisibleEntry(visibleEntries);
                      _searchFocusNode.requestFocus();
                    },
                    decoration: InputDecoration(
                      hintText: "Search site or user",
                      isDense: true,
                      filled: true,
                      fillColor: accent.withAlpha(10),
                      prefixIcon: Icon(Icons.search_rounded, size: 16, color: accent),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: accent.withAlpha(90)),
                      ),
                    ),
                  ),
                  if (visibleEntries.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    _buildSharedProgressBar(
                      accent: accent,
                      onSurface: onSurface,
                      entry: visibleEntries.first,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: visibleEntries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        "No authenticators match your search.",
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 2,
                          color: onSurface.withAlpha(160),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    itemCount: visibleEntries.length + 1,
                    itemBuilder: (BuildContext context, int index) {
                      if (index == visibleEntries.length) {
                        return const Center(child: Text("Logos by Logo.dev"));
                      }
                      final AuthenticatorEntry entry = visibleEntries[index];
                      final GlobalKey<_AuthenticatorTileState> tileKey =
                          _tileKeys.putIfAbsent(entry.id, () => GlobalKey<_AuthenticatorTileState>());
                      return _AuthenticatorTile(
                        key: tileKey,
                        entry: entry,
                        accent: accent,
                        onSurface: onSurface,
                        now: _now,
                        onDelete: () => _deleteEntry(entry),
                        onEdit: () => _editEntry(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyFirstVisibleEntry(List<AuthenticatorEntry> visibleEntries) async {
    if (visibleEntries.isEmpty) return;

    final GlobalKey<_AuthenticatorTileState>? tileKey = _tileKeys[visibleEntries.first.id];
    if (tileKey?.currentState != null && tileKey!.currentContext != null) {
      final RenderBox? box = tileKey.currentContext!.findRenderObject() as RenderBox?;
      if (box != null) {
        final Offset position = box.localToGlobal(box.size.center(Offset.zero));
        WidgetsBinding.instance.handlePointerEvent(PointerDownEvent(
          pointer: 0,
          position: position,
        ));
        WidgetsBinding.instance.handlePointerEvent(PointerUpEvent(
          pointer: 0,
          position: position,
        ));
        return;
      }
    }

    final String code = AuthenticatorManager.generateCode(visibleEntries.first, now: _now);
    await Clipboard.setData(ClipboardData(text: code));
    setState(() {
      _copiedExport = true;
    });
  }

  Widget _buildSharedProgressBar({
    required Color accent,
    required Color onSurface,
    required AuthenticatorEntry entry,
  }) {
    final double progressLeft = (1 - AuthenticatorManager.progress(entry, now: _now)).clamp(0.0, 1.0);
    final int remaining = AuthenticatorManager.secondsRemaining(entry, now: _now);

    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressLeft,
              minHeight: 5,
              backgroundColor: onSurface.withAlpha(16),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          "${remaining}s",
          style: TextStyle(
            fontSize: Design.baseFontSize,
            fontWeight: FontWeight.w700,
            color: onSurface.withAlpha(150),
          ),
        ),
      ],
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.message,
    required this.accent,
    required this.background,
    required this.onClose,
  });

  final String message;
  final Color accent;
  final Color background;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: background,
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, size: 14, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthenticatorPasswordDialog extends StatefulWidget {
  const _AuthenticatorPasswordDialog({
    required this.title,
    required this.confirmLabel,
    required this.message,
    required this.emptyUsesDefault,
    required this.allowEmpty,
    required this.confirmPassword,
  });

  final String title;
  final String confirmLabel;
  final String message;
  final bool emptyUsesDefault;
  final bool allowEmpty;
  final bool confirmPassword;

  @override
  State<_AuthenticatorPasswordDialog> createState() => _AuthenticatorPasswordDialogState();
}

class _AuthenticatorPasswordDialogState extends State<_AuthenticatorPasswordDialog> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      shadowColor: Colors.red,
      elevation: 5,
      surfaceTintColor: userSettings.themeColors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText:
                  widget.allowEmpty && widget.emptyUsesDefault ? 'Password (empty uses "encrypted")' : 'Password',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.confirmPassword) ...<Widget>[
            const SizedBox(height: 10),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_localError != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _localError!,
              style: TextStyle(fontSize: Design.baseFontSize + 2, color: Colors.redAccent),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }

  void _submit() {
    final String password = _passwordController.text;
    String? message;

    if (!widget.allowEmpty && password.trim().isEmpty) {
      message = 'Password is required.';
    } else if (widget.confirmPassword && password != _confirmController.text) {
      message = 'Passwords do not match.';
    }

    if (message != null) {
      setState(() {
        _localError = message;
      });
      return;
    }

    Navigator.of(context).pop(password);
  }
}

class _AuthenticatorTile extends StatefulWidget {
  const _AuthenticatorTile({
    super.key,
    required this.entry,
    required this.accent,
    required this.onSurface,
    required this.now,
    required this.onDelete,
    required this.onEdit,
  });

  final AuthenticatorEntry entry;
  final Color accent;
  final Color onSurface;
  final DateTime now;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_AuthenticatorTile> createState() => _AuthenticatorTileState();
}

class _AuthenticatorTileState extends State<_AuthenticatorTile> {
  bool _hovered = false;
  bool _copied = false;
  late Future<Uint8List?> _logoFuture;

  @override
  void initState() {
    super.initState();
    _logoFuture = AuthenticatorLogoStore.instance.getLogo(widget.entry);
  }

  @override
  void didUpdateWidget(covariant _AuthenticatorTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id ||
        oldWidget.entry.issuer != widget.entry.issuer ||
        oldWidget.entry.accountName != widget.entry.accountName) {
      _logoFuture = AuthenticatorLogoStore.instance.getLogo(widget.entry);
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  Future<void> copyCurrentCode() async {
    final String code = AuthenticatorManager.generateCode(widget.entry, now: widget.now);
    await _copyCode(code);
  }

  @override
  Widget build(BuildContext context) {
    String? code;
    try {
      code = AuthenticatorManager.generateCode(widget.entry, now: widget.now);
    } catch (_) {
      code = null;
    }

    final int remaining = AuthenticatorManager.secondsRemaining(widget.entry, now: widget.now);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _copied = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color:
              _hovered ? userSettings.themeColors.accent.withAlpha(20) : userSettings.themeColors.accent.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered ? userSettings.themeColors.accent.withAlpha(70) : widget.onSurface.withAlpha(20),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: code == null ? null : () => _copyCode(code!),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: userSettings.themeColors.accent.withAlpha(26),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: FutureBuilder<Uint8List?>(
                        future: _logoFuture,
                        builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                          final Uint8List? bytes = snapshot.data;
                          if (bytes != null && bytes.isNotEmpty) {
                            return Image.memory(
                              bytes,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            );
                          }

                          return Text(
                            widget.entry.title.characters.first.toUpperCase(),
                            style: TextStyle(
                              fontSize: Design.baseFontSize + 2,
                              fontWeight: FontWeight.w700,
                              color: userSettings.themeColors.accent,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Design.baseFontSize + 2,
                              fontWeight: FontWeight.w700,
                              color: widget.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.entry.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Design.baseFontSize,
                              color: widget.onSurface.withAlpha(150),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: widget.onSurface.withAlpha(16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        "${remaining}s",
                        style: TextStyle(
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w700,
                          color: widget.onSurface.withAlpha(180),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: widget.onEdit,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: _hovered ? userSettings.themeColors.accent : widget.onSurface.withAlpha(120),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: _hovered ? Colors.redAccent : widget.onSurface.withAlpha(120),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      code == null ? "Invalid secret" : _formatCode(code),
                      style: TextStyle(
                        fontSize: 20,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                        color: code == null ? Colors.redAccent : widget.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _copied ? "Copied" : "Tap to copy",
                      style: TextStyle(
                        fontSize: Design.baseFontSize,
                        fontWeight: FontWeight.w600,
                        color: _copied ? userSettings.themeColors.accent : widget.onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCode(String code) {
    if (code.length <= 6) {
      return '${code.substring(0, 3)} ${code.substring(3)}';
    }

    final int midpoint = (code.length / 2).floor();
    return '${code.substring(0, midpoint)} ${code.substring(midpoint)}';
  }
}

class AuthenticatorLogoStore {
  AuthenticatorLogoStore._();

  static final AuthenticatorLogoStore instance = AuthenticatorLogoStore._();
  static const String randomString =
      "pk_${1 + 1 == 3 ? '' : ''}avbQQ${1 + 1 == 3 ? '' : ''}aLqQgW${1 + 1 == 3 ? '' : ''}v3hvq2${1 + 1 == 3 ? '' : ''}gbe2g";

  final Map<String, Future<Uint8List?>> _inFlight = <String, Future<Uint8List?>>{};

  Future<Uint8List?> getLogo(AuthenticatorEntry entry) async {
    final String query = _queryForEntry(entry);
    if (query.isEmpty) return null;

    final Future<Uint8List?>? current = _inFlight[query];
    if (current != null) return current;

    final Future<Uint8List?> future = _loadLogo(query);
    _inFlight[query] = future;
    final Uint8List? result = await future;
    _inFlight.remove(query);
    return result;
  }

  Future<Uint8List?> _loadLogo(String query) async {
    final File persistedFile = File(_logoFilePathForQuery(query));
    if (persistedFile.existsSync()) {
      final Uint8List bytes = await persistedFile.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    }

    if (File(_missFilePath(query)).existsSync()) return null;

    final String? domain = await _resolveDomain(query);
    if (domain == null || domain.isEmpty) {
      await _writeMissMarker(query);
      return null;
    }

    try {
      final Uri uri = Uri.parse(
        'https://img.logo.dev/$domain?token=$randomString&size=24&retina=true&format=png&theme=dark',
      );
      http.Response response = await http.get(uri);
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        await _writeMissMarker(query);
        return null;
      }

      // final Uint8List? processed = await compute<Uint8List, Uint8List?>(
      //   _prepareAuthenticatorLogo,
      //   Uint8List.fromList(response.bodyBytes),
      // );
      final Uint8List processed = response.bodyBytes;
      if (processed.isEmpty) {
        await _writeMissMarker(query);
        return null;
      }

      final File file = File(_logoFilePathForQuery(query));
      if (!file.existsSync()) {
        await file.create(recursive: true);
      }
      await file.writeAsBytes(processed, flush: true);
      return processed;
    } catch (_) {
      await _writeMissMarker(query);
      return null;
    }
  }

  Future<String?> _resolveDomain(String query) async {
    final String normalizedQuery = query.trim().toLowerCase();
    if (_looksLikeDomain(normalizedQuery)) {
      return normalizedQuery;
    }
    try {
      final Uri uri = Uri.parse('https://www.logo.dev/api/search?q=${Uri.encodeQueryComponent(query)}');
      final http.Response response = await http.get(uri);
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        return null;
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! List) return null;
      for (final dynamic item in decoded) {
        if (item is! Map) continue;
        final String domain = (item['domain'] ?? '').toString().trim().toLowerCase();
        if (domain.isNotEmpty) return domain;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _writeMissMarker(String query) async {
    final File file = File(_missFilePath(query));
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }
    await file.writeAsString('miss', flush: true);
  }

  String get _logoDirectoryPath => '${WinUtils.getTabameAppDataFolder()}\\cache\\authenticator logos';

  String _logoFilePathForQuery(String query) => '$_logoDirectoryPath\\${_safeName(query)}.png';

  String _missFilePath(String query) => '$_logoDirectoryPath\\${_safeName(query)}.miss';

  String _safeName(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _queryForEntry(AuthenticatorEntry entry) {
    if (entry.issuer.trim().isNotEmpty) return entry.issuer.trim();
    if (entry.accountName.contains('@')) {
      return entry.accountName.split('@').first.trim();
    }
    return entry.title.trim();
  }

  bool _looksLikeDomain(String value) {
    return RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(value);
  }
}
