import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/vault_item.dart';
import '../../../models/classes/vault_manager.dart';
import '../../../models/settings.dart';
import '../../widgets/mix_widgets.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/panel_header.dart';
import 'button_authenticator.dart' show AuthenticatorLogoStore;

class VaultsButton extends StatelessWidget {
  const VaultsButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(actionName: "Vaults", icon: const Icon(Icons.lock_rounded), child: () => const VaultsWidget());
  }
}

class VaultsWidget extends StatefulWidget {
  const VaultsWidget({super.key});
  @override
  VaultsWidgetState createState() => VaultsWidgetState();
}

class VaultsWidgetState extends State<VaultsWidget> with SingleTickerProviderStateMixin {
  Map<String, VaultMetadata> vaults = <String, VaultMetadata>{};
  bool _loading = true;
  String? _selectedVaultName;
  VaultData? _decryptedData;
  String? _currentPassword;
  String? _errorMessage;
  bool _copiedAllKeys = false;
  Timer? _copiedAllKeysTimer;

  late final AnimationController _shakeController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  // New Vault Flow
  bool _creating = false;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _passConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadVaults();
  }

  Future<void> _loadVaults() async {
    vaults = await VaultManager.loadAllMetadata();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _copiedAllKeysTimer?.cancel();
    _shakeController.dispose();
    _nameController.dispose();
    _passController.dispose();
    _passConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CancelTraversal(child: _buildHeader(accent, onSurface)),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  width: double.infinity,
                  color: Colors.red.withAlpha(30),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.error_outline_rounded, size: 14, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 1, color: Colors.redAccent, fontWeight: FontWeight.w500),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _errorMessage = null),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              Flexible(child: _buildBody(accent, onSurface)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(Color accent, Color onSurface) {
    if (_decryptedData != null) {
      final int count = _decryptedData!.items.length;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: accent.withAlpha(40)))),
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: () => setState(() {
                _decryptedData = null;
                _currentPassword = null;
                _selectedVaultName = null;
                _errorMessage = null;
              }),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
            ),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: accent.withAlpha(26), borderRadius: BorderRadius.circular(9)),
              alignment: Alignment.center,
              child: Icon(Icons.lock_open_rounded, size: 14, color: accent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _selectedVaultName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Text(
                    count == 1 ? "1 item" : "$count items",
                    style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withAlpha(140)),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _exportAllKeys,
              icon: Icon(
                _copiedAllKeys ? Icons.check_rounded : Icons.copy_all_rounded,
                color: _copiedAllKeys ? Colors.green : accent,
              ),
              tooltip: _copiedAllKeys ? "Copied" : "Copy Keys as JSON",
            ),
            IconButton(
              onPressed: _addNewItem,
              icon: Icon(Icons.add_rounded, color: accent),
              tooltip: "Add Item",
            ),
          ],
        ),
      );
    }

    if (_creating) {
      return PanelHeader(
        title: "New Vault",
        icon: Icons.shield_rounded,
        buttonPressed: () => setState(() {
          _creating = false;
          _errorMessage = null;
        }),
        buttonIcon: Icons.close,
      );
    }

    if (_selectedVaultName != null) {
      return PanelHeader(
        title: "Unlock Vault",
        icon: Icons.lock_clock_rounded,
        buttonPressed: () => setState(() {
          _selectedVaultName = null;
          _errorMessage = null;
          _passController.clear();
        }),
        buttonIcon: Icons.close,
      );
    }

    return PanelHeader(
      title: "Vaults",
      icon: Icons.lock_outline_rounded,
      buttonPressed: () => setState(() => _creating = true),
      buttonIcon: Icons.add,
    );
  }

  Widget _buildBody(Color accent, Color onSurface) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_decryptedData != null) {
      return VaultDetailWidget(
        data: _decryptedData!,
        onSave: (VaultData newData) async {
          await VaultManager.saveVault(_selectedVaultName!, _currentPassword!, newData);
          setState(() => _decryptedData = newData);
        },
        accent: accent,
        onSurface: onSurface,
      );
    }

    if (_creating) return _buildCreationForm(accent, onSurface);

    if (_selectedVaultName != null) return _buildPasswordPrompt(accent, onSurface);

    if (vaults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withAlpha(18)),
                alignment: Alignment.center,
                child: Icon(Icons.lock_outline_rounded, size: 26, color: accent.withAlpha(190)),
              ),
              const SizedBox(height: 14),
              Text("No vaults yet", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onSurface)),
              const SizedBox(height: 6),
              Text(
                "Create an encrypted vault to securely store passwords, keys, and notes.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(160)),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text("Create Vault"),
              ),
            ],
          ),
        ),
      );
    }

    return MouseScrollWidget(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: vaults.keys
              .map((String name) => _VaultRow(
                    name: name,
                    accent: accent,
                    onSurface: onSurface,
                    onTap: () async {
                      final VaultData? data = await VaultManager.decryptVault(name, "n0p@s5");
                      if (data != null) {
                        setState(() {
                          _selectedVaultName = name;
                          _decryptedData = data;
                          _currentPassword = "n0p@s5";
                        });
                      } else {
                        setState(() => _selectedVaultName = name);
                      }
                    },
                    onDelete: () => _confirmDelete(name),
                  ))
              .toList(growable: false),
        ),
      ),
    );
  }

  Widget _buildCreationForm(Color accent, Color onSurface) {
    return MouseScrollWidget(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: accent.withAlpha(26), borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Icon(Icons.shield_rounded, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Create a new encrypted vault to store secrets.",
                    style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(180)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                  _buildField(controller: _nameController, label: "Vault Name", icon: Icons.label_outline_rounded),
                  const SizedBox(height: 10),
                  _buildField(
                      controller: _passController,
                      label: "Password (Optional)",
                      icon: Icons.password_rounded,
                      isObscure: true),
                  const SizedBox(height: 10),
                  _buildField(
                      controller: _passConfirmController,
                      label: "Confirm Password",
                      icon: Icons.check_circle_outline_rounded,
                      isObscure: true,
                      onSubmitted: (_) => _createVault()),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withAlpha(50))),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text("If you lose this password, your data is lost forever.",
                          style: TextStyle(fontSize: Design.baseFontSize, color: Colors.amber))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _createVault,
              icon: const Icon(Icons.add_moderator_rounded, size: 16),
              label: const Text("Create Secure Vault"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordPrompt(Color accent, Color onSurface) {
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (BuildContext context, Widget? child) {
        final double t = _shakeController.value;
        final double dx = math.sin(t * math.pi * 6) * 10 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: <Color>[accent.withAlpha(45), accent.withAlpha(15)]),
                  border: Border.all(color: accent.withAlpha(60)),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.lock_rounded, size: 24, color: accent),
              ),
              const SizedBox(height: 14),
              Text(
                _selectedVaultName ?? '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                "Enter the password to decrypt this vault.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(150)),
              ),
              const SizedBox(height: 18),
              _buildField(
                  controller: _passController,
                  label: "Password",
                  icon: Icons.vpn_key_rounded,
                  isObscure: true,
                  autoFocus: true,
                  onSubmitted: (_) => _unlockVault()),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                        onPressed: () => setState(() {
                              _selectedVaultName = null;
                              _errorMessage = null;
                              _passController.clear();
                            }),
                        child: const Text("Cancel")),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _unlockVault,
                      icon: const Icon(Icons.lock_open_rounded, size: 16),
                      label: const Text("Unlock"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportAllKeys() async {
    final List<String> keys = _decryptedData?.items.map((VaultItem item) => item.key).toList() ?? <String>[];
    await Clipboard.setData(ClipboardData(text: jsonEncode(keys)));

    _copiedAllKeysTimer?.cancel();
    if (!mounted) return;

    setState(() => _copiedAllKeys = true);
    _copiedAllKeysTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copiedAllKeys = false);
      }
    });
  }

  void _createVault() async {
    if (_nameController.text.isEmpty) return;

    final String password = _passController.text.isEmpty ? "n0p@s5" : _passController.text;
    final String confirm = _passConfirmController.text.isEmpty ? "n0p@s5" : _passConfirmController.text;

    if (password != confirm) {
      setState(() => _errorMessage = "Passwords do not match!");
      return;
    }

    await VaultManager.saveVault(_nameController.text, password, VaultData(items: <VaultItem>[]));
    _nameController.clear();
    _passController.clear();
    _passConfirmController.clear();
    setState(() {
      _creating = false;
      _errorMessage = null;
    });
    _loadVaults();
  }

  void _unlockVault() async {
    final String password = _passController.text.isEmpty ? "n0p@s5" : _passController.text;
    final VaultData? data = await VaultManager.decryptVault(_selectedVaultName!, password);
    if (data == null) {
      setState(() => _errorMessage = "Incorrect password or corrupt vault!");
      _shakeController.forward(from: 0);
    } else {
      setState(() {
        _decryptedData = data;
        _currentPassword = password;
        _errorMessage = null;
        _passController.clear();
      });
    }
  }

  void _addNewItem() {
    setState(() {
      _decryptedData!.items.add(VaultItem(key: "New Key", value: ""));
    });
  }

  void _confirmDelete(String name) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Delete Vault?"),
        content: Text("Are you sure you want to delete '$name'? All secrets inside will be destroyed."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              await VaultManager.deleteVault(name);
              if (context.mounted) Navigator.pop(context);
              _loadVaults();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _VaultRow extends StatefulWidget {
  const _VaultRow({
    required this.name,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onDelete,
  });

  final String name;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_VaultRow> createState() => _VaultRowState();
}

class _VaultRowState extends State<_VaultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withAlpha(20) : widget.accent.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _hovered ? widget.accent.withAlpha(70) : widget.onSurface.withAlpha(20)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration:
                        BoxDecoration(color: widget.accent.withAlpha(26), borderRadius: BorderRadius.circular(10)),
                    alignment: Alignment.center,
                    child: Icon(Icons.lock_person_rounded, size: 16, color: widget.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          widget.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: widget.onSurface),
                        ),
                        Text(
                          "Encrypted vault",
                          style: TextStyle(fontSize: Design.baseFontSize, color: widget.onSurface.withAlpha(140)),
                        ),
                      ],
                    ),
                  ),
                  CancelTraversal(
                    child: InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline_rounded,
                            size: 16, color: _hovered ? Colors.redAccent : widget.onSurface.withAlpha(120)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: widget.onSurface.withAlpha(100)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VaultDetailWidget extends StatefulWidget {
  const VaultDetailWidget({
    super.key,
    required this.data,
    required this.onSave,
    required this.accent,
    required this.onSurface,
  });
  final VaultData data;
  final Function(VaultData) onSave;
  final Color accent;
  final Color onSurface;

  @override
  State<VaultDetailWidget> createState() => _VaultDetailWidgetState();
}

class _VaultDetailWidgetState extends State<VaultDetailWidget> {
  int _editingIndex = -1;
  final TextEditingController _keyEdit = TextEditingController();
  final TextEditingController _valEdit = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _keyEdit.dispose();
    _valEdit.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.key_off_rounded, size: 30, color: widget.accent.withAlpha(150)),
              const SizedBox(height: 10),
              Text("This vault is empty",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: widget.onSurface)),
              const SizedBox(height: 6),
              Text(
                "Add a key/value pair to start storing secrets.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: widget.onSurface.withAlpha(160)),
              ),
            ],
          ),
        ),
      );
    }

    final String query = _searchController.text.trim().toLowerCase();
    final List<int> visibleIndices = <int>[
      for (int i = 0; i < widget.data.items.length; i++)
        if (query.isEmpty || widget.data.items[i].key.toLowerCase().contains(query)) i,
    ];

    return MouseScrollWidget(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.data.items.length > 4) ...<Widget>[
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: "Search keys",
                  filled: true,
                  fillColor: widget.accent.withAlpha(10),
                  prefixIcon: Icon(Icons.search_rounded, size: 16, color: widget.accent),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (visibleIndices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text("No matching keys", style: TextStyle(color: widget.onSurface.withAlpha(150))),
                ),
              )
            else
              ...visibleIndices.map((int index) {
                final VaultItem item = widget.data.items[index];
                if (_editingIndex == index) return _buildEditor(index);

                return _VaultItemTile(
                  key: ValueKey<int>(index),
                  item: item,
                  accent: widget.accent,
                  onSurface: widget.onSurface,
                  onEdit: () => setState(() {
                    _editingIndex = index;
                    _keyEdit.text = item.key;
                    _valEdit.text = item.value;
                  }),
                  onDelete: () {
                    widget.data.items.removeAt(index);
                    widget.onSave(widget.data);
                  },
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(int index) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: Design.accent.withAlpha(15), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: <Widget>[
          _buildField(controller: _keyEdit, label: "Key", icon: Icons.key),
          const SizedBox(height: 8),
          _buildField(controller: _valEdit, label: "Value", icon: Icons.blur_linear_outlined),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              IconButton(onPressed: () => setState(() => _editingIndex = -1), icon: const Icon(Icons.close, size: 16)),
              IconButton(
                onPressed: () {
                  widget.data.items[index].key = _keyEdit.text;
                  widget.data.items[index].value = _valEdit.text;
                  widget.onSave(widget.data);
                  setState(() => _editingIndex = -1);
                },
                icon: const Icon(Icons.check, size: 16, color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _buildField(
    {required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
    bool autoFocus = false,
    Function(String)? onSubmitted,
    String? hintText}) {
  return TextField(
    controller: controller,
    obscureText: isObscure,
    autofocus: autoFocus,
    onSubmitted: onSubmitted,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      isDense: true,

      // Use labelText instead of hintText
      labelText: label,
      hintText: hintText,
      floatingLabelBehavior: FloatingLabelBehavior.auto,

      labelStyle: TextStyle(
        fontSize: Design.baseFontSize + 2,
        color: Design.text.withAlpha(110),
      ),

      prefixIcon: Icon(
        icon,
        size: 16,
        color: Design.accent,
      ),

      filled: true,
      fillColor: Design.accent.withAlpha(10),

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 10,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: Design.accent.withAlpha(90),
        ),
      ),
    ),
  );
}

class _VaultItemTile extends StatefulWidget {
  const _VaultItemTile({
    super.key,
    required this.item,
    required this.accent,
    required this.onSurface,
    required this.onEdit,
    required this.onDelete,
  });
  final VaultItem item;
  final Color accent;
  final Color onSurface;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_VaultItemTile> createState() => _VaultItemTileState();
}

class _VaultItemTileState extends State<_VaultItemTile> {
  bool _hovered = false;
  bool _copied = false;
  late Future<Uint8List?> _logoFuture;

  @override
  void initState() {
    super.initState();
    _logoFuture = AuthenticatorLogoStore.instance.getLogoForQuery(widget.item.key.trim());
  }

  @override
  void didUpdateWidget(covariant _VaultItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.key != widget.item.key) {
      _logoFuture = AuthenticatorLogoStore.instance.getLogoForQuery(widget.item.key.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _copied = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
            color: _hovered ? Design.accent.withAlpha(60) : Colors.transparent,
            borderRadius: BorderRadius.circular(10)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.item.value));
              setState(() => _copied = true);
              Timer(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30,
                    height: 30,
                    decoration:
                        BoxDecoration(color: widget.accent.withAlpha(24), borderRadius: BorderRadius.circular(9)),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: FutureBuilder<Uint8List?>(
                      future: _logoFuture,
                      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
                        final Uint8List? bytes = snapshot.data;
                        if (bytes != null && bytes.isNotEmpty) {
                          return Image.memory(bytes, width: 30, height: 30, fit: BoxFit.cover, gaplessPlayback: true);
                        }
                        return Icon(Icons.key_rounded, size: 14, color: widget.accent);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(widget.item.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          _hovered ? widget.item.value : "••••••••",
                          maxLines: 1,
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 1,
                              color: widget.onSurface.withAlpha(150),
                              fontFamily: _hovered ? null : 'monospace'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_copied)
                    Text("Copied!",
                        style: TextStyle(
                            fontSize: Design.baseFontSize, color: widget.accent, fontWeight: FontWeight.bold)),
                  if (_hovered && !_copied) ...<Widget>[
                    InkWell(
                      onTap: widget.onEdit,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.edit_outlined, size: 14, color: widget.accent),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onDelete,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
