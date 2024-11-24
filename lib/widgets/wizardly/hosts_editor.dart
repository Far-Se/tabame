import 'dart:io';

import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../models/win32/win32.dart';

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
    if (mounted) {
      setState(() {});
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!canAccessHosts) return Container(child: const Center(child: Text("Can not access hosts file, you need to open Tabame with Admin. Privileges")));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!canSaveHosts) const Center(child: Text("You need to open Tabame with Admin Privileges to save hosts file!")),
          ListTile(
            onTap: () {
              hostsList.insert(0, "127.0.0.1 google.com");
              setState(() {});
            },
            leading: const Icon(Icons.add),
            title: const Text("Add new entry"),
            trailing: Container(
              height: double.infinity,
              width: 50,
              child: InkWell(
                onTap: () {
                  WinUtils.open(Directory(hostFile).parent.path);
                },
                child: const Tooltip(message: "Open hosts folder", child: Icon(Icons.open_in_browser)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...List<Widget>.generate(hostsList.length, (int index) {
            return HostRow(
                key: UniqueKey(),
                hostLine: hostsList[index],
                onChanged: (String newLine) {
                  print(newLine);
                  hostsList[index] = newLine;
                  if (canSaveHosts) {
                    File(hostFile).writeAsStringSync(hostsList.join("\r\n"));
                  }
                  setState(() {});
                });
          })
        ],
      ),
    );
  }
}

class HostRow extends StatefulWidget {
  final Function(String newLine) onChanged;
  const HostRow({
    super.key,
    required this.hostLine,
    required this.onChanged,
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
    super.dispose();
    addressController.dispose();
    hostsController.dispose();
    commentController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (badLine) return Container();

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
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
                  decoration: const InputDecoration(labelText: "Address", hintText: "Address", isDense: true, border: OutlineInputBorder()),
                  controller: addressController),
            ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
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
                  decoration: const InputDecoration(labelText: "Hosts", hintText: "Hosts", isDense: true, border: OutlineInputBorder()), controller: hostsController),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
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
                // setState(() {});
              },
              child: TextField(
                  decoration: const InputDecoration(labelText: "Comment", hintText: "Comment", isDense: true, border: OutlineInputBorder()),
                  controller: commentController),
            ),
          ),
        ),
        SizedBox(
            width: 70,
            child: Tooltip(
              message: "Enable",
              child: Switch(
                  value: enabled,
                  onChanged: (bool value) {
                    if (widget.hostLine.startsWith("#")) {
                      widget.onChanged(widget.hostLine.replaceFirst('#', '').trim());
                    } else {
                      widget.onChanged("# ${widget.hostLine}");
                    }
                    // setState(() => enabled = !enabled);
                  }),
            ))
      ],
    );
  }
}
