import 'dart:convert';
import 'dart:io';

import 'package:contextual_menu/contextual_menu.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/info_text.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  BookmarksPageState createState() => BookmarksPageState();
}

class BookmarksPageState extends State<BookmarksPage> {
  final TextEditingController folderEmojiController = TextEditingController();
  final TextEditingController folderTitleController = TextEditingController();
  final TextEditingController projectEmojiController = TextEditingController();
  final TextEditingController projectTitleController = TextEditingController();
  final TextEditingController projectPathController = TextEditingController();
  TextEditingController controller = TextEditingController();
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;

  int activeProject = -1;
  double opacity = 0;
  int timerDelay = 300;
  List<double> heights = <double>[];
  @override
  void initState() {
    heights = List<double>.filled(bookmarks.length, 0);
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    folderEmojiController.dispose();
    folderTitleController.dispose();
    projectEmojiController.dispose();
    projectTitleController.dispose();
    projectPathController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTileTheme(
      data: Theme.of(context).listTileTheme.copyWith(horizontalTitleGap: 10),
      child: Column(
        children: <Widget>[
          const InfoText("To open a bookmark, open QuickRun and type b then the name of the bookmark"),
          ListTile(
            title: const Text("Bookmarks", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            leading: Container(
              height: double.infinity,
              width: 50,
              child: const Icon(Icons.add),
            ),
            onTap: () async {
              bookmarks.add(BookmarkGroup(title: "New Project Group", emoji: "✨", bookmarks: <BookmarkInfo>[]));
              heights = List<double>.filled(bookmarks.length, 0);
              await Boxes.updateSettings("projects", jsonEncode(bookmarks));

              setState(() {});
            },
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              dragStartBehavior: DragStartBehavior.down,
              itemCount: bookmarks.length,
              physics: const AlwaysScrollableScrollPhysics(),
              scrollController: ScrollController(),
              itemBuilder: (BuildContext context, int mainIndex) {
                final BookmarkGroup project = bookmarks[mainIndex];
                return Column(
                  key: ValueKey<int>(mainIndex),
                  children: <Widget>[
                    GestureDetector(
                      onSecondaryTap: () {
                        Menu menu = Menu(
                          items: <MenuItem>[
                            MenuItem(
                                label: 'Delete',
                                onClick: (_) async {
                                  bookmarks.removeAt(mainIndex);
                                  heights = List<double>.filled(bookmarks.length, 0);
                                  activeProject = -1;

                                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                                  setState(() {});
                                }),
                          ],
                        );
                        popUpContextualMenu(menu, placement: Placement.bottomRight);
                      },
                      child: ListTile(
                        leading: Text(project.emoji),
                        title: Text(project.title),
                        onTap: () {
                          if (activeProject == mainIndex) {
                            activeProject = -1;
                          } else {
                            activeProject = mainIndex;
                          }
                          heights = List<double>.filled(bookmarks.length, 0);
                          setState(() {});
                          if (activeProject != -1) {
                            Future<void>.delayed(const Duration(milliseconds: 100), () {
                              if (!mounted) return;
                              heights[mainIndex] = double.infinity;
                              setState(() {});
                            });
                          }
                        },
                        trailing: Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: Container(
                            width: 50,
                            height: double.infinity,
                            //! Add and edit Project Folder
                            child: Row(children: <Widget>[
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                    child: const Icon(Icons.edit),
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          folderEmojiController.value = TextEditingValue(text: project.emoji);
                                          folderTitleController.value = TextEditingValue(text: project.title);

                                          return AlertDialog(
                                            content: Container(
                                                width: 300,
                                                height: 500,
                                                foregroundDecoration: BoxDecoration(
                                                  border: Border.all(color: Colors.black.withOpacity(0.5)),
                                                  // color: Colors.purple,
                                                ),
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.start,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: <Widget>[
                                                    TextField(
                                                      decoration: InputDecoration(
                                                        labelText: "Emoji ( Press Win + . to toggle Emoji Picker)",
                                                        hintText: "Emoji ( Press Win + . to toggle Emoji Picker)",
                                                        isDense: true,
                                                        border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                                      ),
                                                      controller: folderEmojiController,
                                                      // inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(1)],
                                                      style: const TextStyle(fontSize: 14),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    TextField(
                                                      autofocus: true,
                                                      decoration: InputDecoration(
                                                        labelText: "Title",
                                                        hintText: "Title",
                                                        isDense: true,
                                                        border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                                      ),
                                                      controller: folderTitleController,
                                                      style: const TextStyle(fontSize: 14),
                                                    ),
                                                    const SizedBox(height: 10),
                                                  ],
                                                )),
                                            actions: <Widget>[
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: const Text("Cancel"),
                                              ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  bookmarks.removeAt(mainIndex);
                                                  heights = List<double>.filled(bookmarks.length, 0);
                                                  activeProject = -1;

                                                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                                                  setState(() {});
                                                  Navigator.of(context).pop();
                                                },
                                                child: Text("Delete", style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                              ),
                                              ElevatedButton(
                                                onPressed: () async {
                                                  bookmarks[mainIndex].emoji = folderEmojiController.value.text.truncate(2);
                                                  bookmarks[mainIndex].title = folderTitleController.value.text;
                                                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                                                  setState(() {});
                                                  Navigator.of(context).pop();
                                                },
                                                child: Text("Save", style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                              ),
                                            ],
                                          );
                                        },
                                      ).then((_) {});
                                    }),
                              ),
                              Expanded(
                                flex: 2,
                                child: InkWell(
                                  child: const Icon(Icons.add),
                                  onTap: () async {
                                    bookmarks[mainIndex].bookmarks.add(BookmarkInfo(emoji: "🎀", title: "New Project", stringToExecute: "C:\\"));
                                    await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                                    if (activeProject != mainIndex) {
                                      heights = List<double>.filled(bookmarks.length, 0);
                                      activeProject = mainIndex;
                                      setState(() {});
                                      Future<void>.delayed(const Duration(milliseconds: 100), () {
                                        if (!mounted) return;
                                        heights[mainIndex] = double.infinity;
                                        setState(() {});
                                      });
                                    } else {
                                      setState(() {});
                                    }
                                  },
                                ),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: Duration(milliseconds: timerDelay),
                      child: Container(
                        constraints: BoxConstraints(maxHeight: heights[mainIndex]),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 40, 0),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            dragStartBehavior: DragStartBehavior.down,
                            itemCount: bookmarks[mainIndex].bookmarks.length,
                            physics: const AlwaysScrollableScrollPhysics(),
                            scrollController: ScrollController(),
                            itemBuilder: (BuildContext context, int index) {
                              final BookmarkInfo projectItem = bookmarks[mainIndex].bookmarks[index];
                              return ListTile(
                                key: ValueKey<int>(index),
                                leading: Text(projectItem.emoji),
                                title: Text(projectItem.title),
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      projectEmojiController.value = TextEditingValue(text: projectItem.emoji);
                                      projectTitleController.value = TextEditingValue(text: projectItem.title);
                                      projectPathController.value = TextEditingValue(text: projectItem.stringToExecute);
                                      return AlertDialog(
                                        content: Container(
                                            width: 400,
                                            height: 250,
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: <Widget>[
                                                TextField(
                                                  decoration: InputDecoration(
                                                    labelText: "Emoji ( Press Win + . to toggle Emoji Picker)",
                                                    hintText: "Emoji ( Press Win + . to toggle Emoji Picker)",
                                                    isDense: true,
                                                    border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                                  ),
                                                  controller: projectEmojiController,
                                                  // inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(1)],
                                                  style: const TextStyle(fontSize: 14),
                                                ),
                                                const SizedBox(height: 5),
                                                TextField(
                                                  autofocus: true,
                                                  decoration: InputDecoration(
                                                    labelText: "Title",
                                                    hintText: "Title",
                                                    isDense: true,
                                                    border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                                  ),
                                                  controller: projectTitleController,
                                                  style: const TextStyle(fontSize: 14),
                                                ),
                                                const SizedBox(height: 5),
                                                Row(
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  mainAxisSize: MainAxisSize.max,
                                                  children: <Widget>[
                                                    Expanded(
                                                      flex: 2,
                                                      child: TextField(
                                                        decoration: InputDecoration(
                                                          labelText: "Path to execute",
                                                          hintText: "Path to execute",
                                                          isDense: true,
                                                          border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                                        ),
                                                        controller: projectPathController,
                                                        style: const TextStyle(fontSize: 14),
                                                      ),
                                                    ),
                                                    SizedBox(
                                                      width: 30,
                                                      height: 50,
                                                      child: Column(
                                                        children: <Widget>[
                                                          Container(
                                                            width: 30,
                                                            height: 25,
                                                            child: Tooltip(
                                                              message: "Pick a file.",
                                                              child: InkWell(
                                                                onTap: () async {
                                                                  final OpenFilePicker file = OpenFilePicker()
                                                                    ..filterSpecification = <String, String>{
                                                                      'All Files': '*.*',
                                                                    }
                                                                    ..defaultFilterIndex = 0
                                                                    ..defaultExtension = 'exe'
                                                                    ..title = 'Select any file';

                                                                  final File? result = file.getFile();
                                                                  if (result != null) {
                                                                    if (!mounted) return;
                                                                    projectItem.stringToExecute = result.path;
                                                                    projectPathController.value = TextEditingValue(text: result.path);
                                                                    setState(() {});
                                                                  }
                                                                },
                                                                child: Container(height: double.infinity, child: const Icon(Icons.file_open, size: 20)),
                                                              ),
                                                            ),
                                                          ),
                                                          Container(
                                                            width: 30,
                                                            height: 25,
                                                            child: Tooltip(
                                                              message: "Pick a folder.",
                                                              preferBelow: true,
                                                              child: InkWell(
                                                                onTap: () async {
                                                                  // final String result = await pickFolder();
                                                                  final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
                                                                  final Directory? dir = dirPicker.getDirectory();
                                                                  if (dir == null) return;
                                                                  String result = dir.path;
                                                                  if (result == "") return;
                                                                  if (!mounted) return;
                                                                  projectItem.stringToExecute = result;
                                                                  projectPathController.value = TextEditingValue(text: result);
                                                                  setState(() {});
                                                                },
                                                                child: Container(height: double.infinity, child: const Icon(Icons.folder_copy, size: 20)),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Text("You can Write:\n - a Folder Path or file to open\n - a command like: code C:\\somepath\\\n - a link",
                                                    style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), fontSize: 12))
                                              ],
                                            )),
                                        actions: <Widget>[
                                          TextButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            child: const Text("Cancel"),
                                          ),
                                          ElevatedButton(
                                            onPressed: () async {
                                              bookmarks[mainIndex].bookmarks.removeAt(index);
                                              await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                                              setState(() {});
                                              Navigator.of(context).pop();
                                            },
                                            child: Text("Delete", style: TextStyle(color: Theme.of(context).colorScheme.error)),
                                          ),
                                          ElevatedButton(
                                            onPressed: () async {
                                              bookmarks[mainIndex].bookmarks[index].emoji = projectEmojiController.value.text.truncate(2);
                                              bookmarks[mainIndex].bookmarks[index].title = projectTitleController.value.text;
                                              bookmarks[mainIndex].bookmarks[index].stringToExecute = projectPathController.value.text;
                                              await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                                              setState(() {});
                                              Navigator.of(context).pop();
                                            },
                                            child: Text("Save", style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                                          ),
                                        ],
                                      );
                                    },
                                  ).then((_) {});
                                },
                                trailing: Container(
                                  height: double.infinity,
                                  width: 50,
                                  padding: const EdgeInsets.only(right: 15),
                                  child: InkWell(
                                    child: const Icon(Icons.bug_report_outlined),
                                    onTap: () {
                                      WinUtils.open(projectItem.stringToExecute, parseParamaters: true);
                                      setState(() {});
                                    },
                                  ),
                                ),
                              );
                            },
                            onReorder: (int oldIndex, int newIndex) async {
                              if (oldIndex < newIndex) newIndex -= 1;
                              final BookmarkInfo item = bookmarks[mainIndex].bookmarks.removeAt(oldIndex);
                              bookmarks[mainIndex].bookmarks.insert(newIndex, item);
                              await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                    )
                  ],
                );
              },
              onReorder: (int oldIndex, int newIndex) async {
                activeProject = -1;
                if (oldIndex < newIndex) newIndex -= 1;
                final BookmarkGroup item = bookmarks.removeAt(oldIndex);
                bookmarks.insert(newIndex, item);
                final double hh = heights[oldIndex];
                heights[oldIndex] = heights[newIndex];
                heights[newIndex] = hh;
                activeProject = newIndex;
                timerDelay = 50;
                await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                setState(() {});
                Future<void>.delayed(const Duration(milliseconds: 500), () => timerDelay = 300);
              },
            ),
          ),
        ],
      ),
    );
  }
}
