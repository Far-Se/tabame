import 'dart:io';

import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/mini_switch.dart';

class HostsEditor extends StatefulWidget {
  const HostsEditor({super.key});
  @override
  HostsEditorState createState() => HostsEditorState();
}

class HostsEditorState extends State<HostsEditor> {
  bool canAccessHosts = false;
  bool canSaveHosts = true;
  List<String> hostsList = <String>[];
  final String hostFile = "${WinUtils.getKnownFolder(FOLDERID_System)}\\drivers\\etc\\hosts";
  @override
  void initState() {
    super.initState();
    readHostsFile();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<bool> readHostsFile() async {
    try {
      File(hostFile).readAsLinesSync();
    } catch (e) {
      canAccessHosts = false;
      return false;
    }
    try {
      File(hostFile).writeAsStringSync("xx", mode: FileMode.append);
    } catch (e) {
      canSaveHosts = false;
    }
    canAccessHosts = true;
    final Future<List<String>> futureLines = File(hostFile).readAsLines().catchError((dynamic e) => <String>[""]);
    hostsList = await futureLines;
    hostsList.removeWhere((String e) => e.isEmpty);
    if (mounted) {
      setState(() {});
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color background = userSettings.themeColors.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    if (!canAccessHosts) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.18)),
          ),
          child: const Row(
            children: <Widget>[
              Icon(Icons.admin_panel_settings_outlined),
              SizedBox(width: 12),
              Expanded(child: Text("Cannot access the hosts file. Open Tabame with administrator privileges.")),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(accent, background, onSurface),
          if (!canSaveHosts) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "Open Tabame with administrator privileges to save changes.",
                style: TextStyle(
                    fontSize: Design.baseFontSize + 2, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _buildToolbar(accent, onSurface),
          const SizedBox(height: 12),
          _buildEntriesSection(accent, onSurface),
        ],
      ),
    );
  }

  Widget _buildHeader(Color accent, Color background, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: onSurface.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.dns_rounded, color: accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text("Hosts File", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          hostFile,
                          style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withValues(alpha: 0.6)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: canSaveHosts
                ? () {
                    hostsList.insert(0, "127.0.0.1 google.com");
                    setState(() {});
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("ADD", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              "${hostsList.length} entries loaded",
              style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  color: onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: readHostsFile,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text("Reload"),
          ),
          const SizedBox(width: 8),
          _ToolbarIconButton(
            icon: Icons.folder_open_rounded,
            tooltip: "Open hosts folder",
            accent: accent,
            onTap: () => WinUtils.open(Directory(hostFile).parent.path),
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesSection(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text("Entries", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text("Edit address, host, and comment fields directly. Changes save automatically when allowed.",
                        style: TextStyle(fontSize: Design.baseFontSize + 2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List<Widget>.generate(hostsList.length, (int index) {
            return HostRow(
              key: UniqueKey(),
              hostLine: hostsList[index],
              canSaveHosts: canSaveHosts,
              onDelete: () {
                hostsList.removeAt(index);
                if (canSaveHosts) {
                  File(hostFile)
                      .writeAsStringSync(hostsList.where((String line) => line.trim().isNotEmpty).join("\r\n"));
                }
                setState(() {});
              },
              onChanged: (String newLine) {
                hostsList[index] = newLine;
                if (canSaveHosts) {
                  File(hostFile)
                      .writeAsStringSync(hostsList.where((String line) => line.trim().isNotEmpty).join("\r\n"));
                }
                setState(() {});
              },
            );
          }),
        ],
      ),
    );
  }
}

class HostRow extends StatefulWidget {
  final Function(String newLine) onChanged;
  final VoidCallback onDelete;
  final bool canSaveHosts;
  const HostRow({
    super.key,
    required this.hostLine,
    required this.onChanged,
    required this.onDelete,
    required this.canSaveHosts,
  });

  final String hostLine;

  @override
  State<HostRow> createState() => _HostRowState();
}

class _HostRowState extends State<HostRow> {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController hostsController = TextEditingController();
  final TextEditingController commentController = TextEditingController();
  bool enabled = false;
  bool badLine = false;
  String address = "";
  String hosts = "";
  String comment = "";
  @override
  void initState() {
    super.initState();
    final String line = widget.hostLine.trim();
    enabled = !line.startsWith("#");
    final RegExpMatch? out = RegExp(r"^(?:#\W+?)?(localhost|[\d\.:]+)\W+([\w\.]+)(?:\W+?#(.*?))?\W?$").firstMatch(line);
    if (out == null) {
      badLine = true;
      return;
    }
    address = addressController.text = out.group(1) ?? "";
    hosts = hostsController.text = out.group(2) ?? "";
    comment = commentController.text = out.group(3) ?? "";
  }

  @override
  void dispose() {
    addressController.dispose();
    hostsController.dispose();
    commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (badLine) return Container();
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled ? accent.withValues(alpha: 0.035) : onSurface.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: enabled ? accent.withValues(alpha: 0.12) : onSurface.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: enabled ? accent.withValues(alpha: 0.12) : onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(enabled ? Icons.check_rounded : Icons.block_rounded,
                      size: 16, color: enabled ? accent : onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hostsController.text.isEmpty ? "Host Entry" : hostsController.text,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                MiniToggleSwitch(
                  value: enabled,
                  onChanged: widget.canSaveHosts
                      ? (bool value) {
                          if (widget.hostLine.startsWith("#")) {
                            widget.onChanged(widget.hostLine.replaceFirst('#', '').trim());
                          } else {
                            widget.onChanged("# ${widget.hostLine}");
                          }
                        }
                      : null,
                ),
                const SizedBox(width: 6),
                _ToolbarIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: "Delete entry",
                  accent: Colors.redAccent,
                  onTap: widget.canSaveHosts ? widget.onDelete : () {},
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Focus(
                      onFocusChange: (bool f) {
                        if (addressController.text.isEmpty) {
                          widget.onChanged("");
                          return;
                        }
                        if (f) return;
                        String newLine = widget.hostLine;
                        newLine = newLine.replaceFirst(address, addressController.text);
                        widget.onChanged(newLine);
                      },
                      child: TextField(
                        enabled: widget.canSaveHosts,
                        decoration: const InputDecoration(
                            labelText: "Address", hintText: "Address", isDense: true, border: OutlineInputBorder()),
                        controller: addressController,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Focus(
                      onFocusChange: (bool f) {
                        if (f) return;
                        if (hostsController.text.isEmpty) {
                          widget.onChanged("");
                          return;
                        }
                        String newLine = widget.hostLine;
                        newLine = newLine.replaceFirst(hosts, hostsController.text);
                        widget.onChanged(newLine);
                      },
                      child: TextField(
                        enabled: widget.canSaveHosts,
                        decoration: const InputDecoration(
                            labelText: "Host", hintText: "Host", isDense: true, border: OutlineInputBorder()),
                        controller: hostsController,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Focus(
                    onFocusChange: (bool f) {
                      if (f) return;
                      String newLine = widget.hostLine;
                      if (commentController.text.isEmpty) {
                        newLine = newLine.replaceFirst(RegExp(r' #.*?$'), "");
                      } else if (comment.isEmpty) {
                        newLine += " #${commentController.text}";
                      } else {
                        newLine = newLine.replaceFirst("#$comment", "#${commentController.text}");
                      }
                      widget.onChanged(newLine);
                    },
                    child: TextField(
                      enabled: widget.canSaveHosts,
                      decoration: const InputDecoration(
                          labelText: "Comment", hintText: "Comment", isDense: true, border: OutlineInputBorder()),
                      controller: commentController,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color accent;
  final VoidCallback onTap;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Icon(icon, size: 16, color: accent),
        ),
      ),
    );
  }
}
