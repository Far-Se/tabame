import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/vault_item.dart';
import '../../../models/classes/vault_manager.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../widgets/mouse_scroll_widget.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

class VaultButton extends StatefulWidget {
  const VaultButton({super.key});
  @override
  VaultButtonState createState() => VaultButtonState();
}

class VaultButtonState extends State<VaultButton> {
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Vault",
      icon: const Icon(Icons.lock_rounded),
      onTap: () async {
        showQuickMenuModal(context: context, child: const VaultsWidget());
      },
    );
  }
}

class VaultsWidget extends StatefulWidget {
  const VaultsWidget({super.key});
  @override
  VaultsWidgetState createState() => VaultsWidgetState();
}

class VaultsWidgetState extends State<VaultsWidget> {
  Map<String, VaultMetadata> vaults = <String, VaultMetadata>{};
  bool _loading = true;
  String? _selectedVaultName;
  VaultData? _decryptedData;
  String? _currentPassword;
  String? _errorMessage;
  bool _copiedAllKeys = false;
  Timer? _copiedAllKeysTimer;

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
    _nameController.dispose();
    _passController.dispose();
    _passConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(accent, onSurface),
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
                          style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w500),
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
            Text(_selectedVaultName!, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
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
        accent: accent,
        icon: Icons.shield_rounded,
        boldFont: true,
        buttonPressed: () => setState(() {
          _creating = false;
          _errorMessage = null;
        }),
        buttonIcon: Icons.close,
      );
    }

    return PanelHeader(
      title: "Vaults",
      accent: accent,
      icon: Icons.lock_outline_rounded,
      boldFont: true,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.lock_open_rounded, size: 48, color: onSurface.withAlpha(51)),
            const SizedBox(height: 16),
            Text("No vaults yet", style: TextStyle(color: onSurface.withAlpha(150))),
          ],
        ),
      );
    }

    return MouseScrollWidget(
      child: Material(
        color: Colors.transparent,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: vaults.length,
          itemBuilder: (BuildContext context, int index) {
            final String name = vaults.keys.elementAt(index);
            return ListTile(
              leading: Icon(Icons.lock_person_rounded, size: 20, color: accent.withAlpha(200)),
              title: Text(name, style: const TextStyle(fontSize: 14)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                onPressed: () => _confirmDelete(name),
              ),
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
            );
          },
        ),
      ),
    );
  }

  Widget _buildCreationForm(Color accent, Color onSurface) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildField(_nameController, "Vault Name", Icons.label_outline_rounded),
          const SizedBox(height: 12),
          _buildField(_passController, "Password (Optional)", Icons.password_rounded, isObscure: true),
          const SizedBox(height: 12),
          _buildField(_passConfirmController, "Confirm Password", Icons.check_circle_outline_rounded,
              isObscure: true, onSubmitted: (_) => _createVault()),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.amber.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withAlpha(50))),
            child: const Row(
              children: <Widget>[
                Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                    child: Text("IMPORTANT: If you lose this password, your data is lost forever.",
                        style: TextStyle(fontSize: 10, color: Colors.amber))),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _createVault, child: const Text("Create Secure Vault")),
        ],
      ),
    );
  }

  Widget _buildPasswordPrompt(Color accent, Color onSurface) {
    return Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text("Unlock '$_selectedVaultName'", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _buildField(_passController, "Enter Password", Icons.vpn_key_rounded,
                  isObscure: true, autoFocus: true, onSubmitted: (_) => _unlockVault()),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  TextButton(
                      onPressed: () => setState(() {
                            _selectedVaultName = null;
                            _errorMessage = null;
                          }),
                      child: const Text("Cancel")),
                  const Spacer(),
                  ElevatedButton(onPressed: _unlockVault, child: const Text("Unlock")),
                ],
              ),
            ],
          ),
        ));
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon,
      {bool isObscure = false, bool autoFocus = false, Function(String)? onSubmitted}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      autofocus: autoFocus,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 16),
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
              Navigator.pop(context);
              _loadVaults();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
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

  @override
  void dispose() {
    _keyEdit.dispose();
    _valEdit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseScrollWidget(
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        itemCount: widget.data.items.length,
        itemBuilder: (BuildContext context, int index) {
          final VaultItem item = widget.data.items[index];
          if (_editingIndex == index) return _buildEditor(index);

          return _VaultItemTile(
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
        },
      ),
    );
  }

  Widget _buildEditor(int index) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: widget.accent.withAlpha(15), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: <Widget>[
          TextField(
              controller: _keyEdit,
              decoration: const InputDecoration(labelText: "Key", isDense: true),
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
              controller: _valEdit,
              decoration: const InputDecoration(labelText: "Value", isDense: true),
              style: const TextStyle(fontSize: 12)),
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

class _VaultItemTile extends StatefulWidget {
  const _VaultItemTile({
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
            color: _hovered ? widget.accent.withAlpha(60) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.item.value));
            setState(() => _copied = true);
            Timer(const Duration(seconds: 2), () {
              if (mounted) setState(() => _copied = false);
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.item.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(
                        _hovered ? widget.item.value : "••••••••",
                        style: TextStyle(
                            fontSize: 11,
                            color: widget.onSurface.withAlpha(150),
                            fontFamily: _hovered ? null : 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_copied)
                  Text("Copied!", style: TextStyle(fontSize: 10, color: widget.accent, fontWeight: FontWeight.bold)),
                if (_hovered && !_copied) ...<Widget>[
                  IconButton(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                  const SizedBox(width: 8),
                  IconButton(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
