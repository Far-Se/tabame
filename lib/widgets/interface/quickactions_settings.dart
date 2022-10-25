// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/util/quick_actions.dart';
import '../widgets/info_text.dart';
import '../widgets/text_input.dart';

class QuickActionsSettings extends StatefulWidget {
  const QuickActionsSettings({Key? key}) : super(key: key);
  @override
  QuickActionsSettingsState createState() => QuickActionsSettingsState();
}

class QuickActionsSettingsState extends State<QuickActionsSettings> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<QuickActions> quickActions = Boxes.quickActions;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Center(child: InfoText("You can bind QuickActions Menu to a specific HotKey or an Hotkey Trigger in Hotkeys tab")),
        const SizedBox(height: 10),
        ListTile(
          onTap: () {
            quickActions.add(QuickActions(name: "new", type: quickActionsType.first, value: "0"));
            Boxes.updateSettings("quickActions", jsonEncode(quickActions));
            setState(() {});
          },
          leading: const Icon(Icons.add),
          title: const Text("Add"),
          dense: true,
        ),
        SingleChildScrollView(
          controller: ScrollController(),
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            shrinkWrap: true,
            dragStartBehavior: DragStartBehavior.down,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollController: ScrollController(),
            itemBuilder: (BuildContext context, int index) {
              return ListTile(
                minLeadingWidth: 10,
                dense: true,
                style: ListTileStyle.drawer,
                minVerticalPadding: 0,
                contentPadding: const EdgeInsets.fromLTRB(20, 0, 30, 0),
                //
                key: ValueKey<int>(index),
                title: Text(quickActions.elementAt(index).name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: "Remove",
                  onPressed: () async {
                    quickActions.removeAt(index);
                    await Boxes.updateSettings("quickActions", jsonEncode(quickActions));
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                onTap: () {
                  showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          scrollable: false,
                          content: Container(
                            height: 300,
                            width: 400,
                            child: SingleChildScrollView(
                              controller: ScrollController(),
                              child: QuickActionEdit(
                                leAction: quickActions.elementAt(index).copyWith(),
                                onSaved: (QuickActions n) {
                                  quickActions[index] = n.copyWith();
                                  Boxes.updateSettings("quickActions", jsonEncode(quickActions));
                                  setState(() {});
                                },
                              ),
                            ),
                          ),
                        );
                      });
                },
              );
            },
            itemCount: quickActions.length,
            onReorder: (int oldIndex, int newIndex) {
              if (oldIndex < newIndex) newIndex -= 1;
              final QuickActions item = quickActions.removeAt(oldIndex);
              quickActions.insert(newIndex, item);

              setState(() {});
              Boxes.updateSettings("quickActions", jsonEncode(quickActions));
            },
          ),
        )
      ],
    );
  }
}

class QuickActionEdit extends StatefulWidget {
  final QuickActions leAction;
  final void Function(QuickActions hotkey) onSaved;
  const QuickActionEdit({
    Key? key,
    required this.leAction,
    required this.onSaved,
  }) : super(key: key);
  @override
  QuickActionEditState createState() => QuickActionEditState();
}

class QuickActionEditState extends State<QuickActionEdit> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Align(
              alignment: Alignment.topRight,
              child: OutlinedButton(
                onPressed: () {
                  widget.onSaved(widget.leAction);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 50,
                  child: const Text(
                    "Cancel",
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: ElevatedButton(
                onPressed: () {
                  widget.onSaved(widget.leAction);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 70,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      const Icon(Icons.save),
                      Text(
                        "Save",
                        style: TextStyle(color: Theme.of(context).backgroundColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        TextInput(
          labelText: "Name",
          onChanged: (String v) {
            widget.leAction.name = v;
            setState(() {});
          },
          value: widget.leAction.name,
        ),
        DropdownButton<String>(
          isExpanded: true,
          value: widget.leAction.type,
          icon: const Icon(Icons.arrow_downward),
          onChanged: (String? newValue) {
            widget.leAction.type = newValue ?? quickActionsType.first;
            if (widget.leAction.type != quickActionsType.first) {
              widget.leAction.value = "";
            } else {
              widget.leAction.value = "0";
            }
            setState(() {});
          },
          items: quickActionsType.map<DropdownMenuItem<String>>((String value) {
            return DropdownMenuItem<String>(value: value, child: Text(value), alignment: Alignment.center);
          }).toList(),
        ),
        if (widget.leAction.type == quickActionsType.first)
          DropdownButton<int>(
            isExpanded: true,
            value: int.tryParse(widget.leAction.value) ?? 0,
            icon: const Icon(Icons.arrow_downward),
            onChanged: (int? newValue) {
              widget.leAction.value = newValue.toString();
              setState(() {});
            },
            items: quickActionsList.map<DropdownMenuItem<int>>((String value) {
              return DropdownMenuItem<int>(value: quickActionsList.indexWhere((String element) => element == value), child: Text(value), alignment: Alignment.center);
            }).toList(),
          )
        else if (quickActionsType.indexOf(widget.leAction.type) > 3 && quickActionsType.indexOf(widget.leAction.type) < 7)
          TextInput(
            labelText: "Value",
            onChanged: (String e) {
              widget.leAction.value = e;
              setState(() {});
            },
            value: widget.leAction.value,
          )
      ],
    );
  }
}
