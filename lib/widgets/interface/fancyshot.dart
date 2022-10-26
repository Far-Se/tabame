// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:tabamewin32/tabamewin32.dart';
// import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/info_text.dart';
import '../widgets/mouse_scroll_widget.dart';

class Fancyshot extends StatefulWidget {
  const Fancyshot({Key? key}) : super(key: key);
  @override
  FancyshotState createState() => FancyshotState();
}

class FancyshotState extends State<Fancyshot> {
  final List<List<double>> aspectRatioList = <List<double>>[
    <double>[1, 1],
    <double>[3 / 2, 2 / 3],
    <double>[4 / 3, 3 / 4],
    <double>[16 / 9, 9 / 16]
  ];
  final FancyShotProfile defaultProfile = FancyShotProfile(
    name: "Default",
    backgroundPadding: 10,
    imagePadding: 0,
    backgroundType: BackgroundType.transparent,
    backgroundImage: "resources/gradient/gradient1.jpg",
    borderRadius: 5,
    shadowSpread: 1,
    shadowRadius: 1,
    backgroundBlur: 0,
    background: 0,
    aspectRatio: 0,
    width: 0,
    height: 0,
    watermark: "",
  );
  late FancyShotProfile filters;

  Uint8List? capture;
  Color? bgColor;
  // final List<String> profiles = <String>[""];
  final List<FancyShotProfile> profiles = Boxes.getSavedMap<FancyShotProfile>(FancyShotProfile.fromJson, "fancyShotProfile", def: <FancyShotProfile>[
    FancyShotProfile(
      name: "Default",
      backgroundPadding: 10,
      imagePadding: 0,
      backgroundType: BackgroundType.transparent,
      backgroundImage: "resources/gradient/gradient1.jpg",
      borderRadius: 5,
      shadowSpread: 1,
      shadowRadius: 1,
      backgroundBlur: 0,
      background: 0,
      aspectRatio: 0,
      width: 0,
      height: 0,
      watermark: "",
    ),
    FancyShotProfile(
      name: "Self Background",
      backgroundPadding: 16,
      imagePadding: 7.5,
      backgroundType: BackgroundType.self,
      backgroundImage: "resources/gradient/gradient1.jpg",
      borderRadius: 8,
      shadowSpread: 3,
      shadowRadius: 6,
      backgroundBlur: 8,
      background: 0,
      aspectRatio: 0,
      width: 0,
      height: 0,
      watermark: "",
    ),
    FancyShotProfile(
      name: "Image Background",
      backgroundPadding: 28,
      imagePadding: 7.5,
      backgroundType: BackgroundType.stock,
      backgroundImage: "resources/gradient/gradient7.jpg",
      borderRadius: 5,
      shadowSpread: 3,
      shadowRadius: 6,
      backgroundBlur: 18,
      background: 0,
      aspectRatio: 0,
      width: 0,
      height: 0,
      watermark: "",
    )
  ]);
  final List<String> profilesName = <String>[""];
  int aspectRatio = 0;
  String? selectedProfile;
  final TextEditingController textEditingController = TextEditingController();

  bool capturing = false;

  TextEditingController watermarkTextController = TextEditingController();
  TextEditingController skewPerspectiveController = TextEditingController();

  bool closeOnAction = true;

  String copyMessage = "Copy";
  final WinClipboard winClipboard = WinClipboard();
  @override
  void initState() {
    super.initState();
    initializeGDI();
    filters = defaultProfile.copyWith();
    if (profiles.isEmpty) profiles.add(defaultProfile);
    profilesName.addAll(profiles.map((FancyShotProfile e) => e.name));
    String? profile = Boxes.pref.getString("fancyshot");
    profile ??= "Default";
    final int i = profiles.indexWhere((FancyShotProfile element) => element.name == profile);
    if (i >= 0) {
      selectedProfile = profile;
      filters = profiles[i].copyWith();
      watermarkTextController.text = filters.watermark;
      skewPerspectiveController.text = filters.skewPerspective.toString();
    }

    if (profilesName.length > 1) profilesName.remove("");
    loadCaptureFile();
  }

  @override
  void dispose() {
    textEditingController.dispose();
    watermarkTextController.dispose();
    skewPerspectiveController.dispose();
    super.dispose();
  }

  img.Image? photo;
  void loadCaptureFile() async {
    final String temp = WinUtils.getTempFolder();
    if (File("$temp\\capture.png").existsSync()) {
      capture = File("$temp\\capture.png").readAsBytesSync();
      photo = img.decodeImage(capture!);
      int pixel32 = photo!.getPixelSafe(0, 0);
      int hex = abgrToArgb(pixel32);
      bgColor = Color(hex);
    } else {
      capture = null;
    }
  }

  int abgrToArgb(int argbColor) {
    int r = (argbColor >> 16) & 0xFF;
    int b = argbColor & 0xFF;
    return (argbColor & 0xFF00FF00) | (b << 16) | r;
  }

  ScreenshotController screenshotController = ScreenshotController();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 20),
        if (capture != null)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                //1 screenshot
                photo == null
                    ? Container()
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 450),
                        decoration: BoxDecoration(border: Border.all(width: 1, color: Colors.black26.withOpacity(0.5))),
                        child: MouseScrollWidget(
                          scrollDirection: Axis.horizontal,
                          child: MouseScrollWidget(
                              scrollDirection: Axis.vertical,
                              child: Screenshot<Widget>(
                                controller: screenshotController,
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: ClipRect(
                                    child: Container(
                                      padding: EdgeInsets.all(filters.backgroundPadding.ceil().toDouble()),
                                      decoration: filters.backgroundType == BackgroundType.stock
                                          ? BoxDecoration(
                                              image: DecorationImage(
                                                image: AssetImage(filters.backgroundImage),
                                                fit: BoxFit.cover,
                                              ),
                                            )
                                          : filters.backgroundType == BackgroundType.self
                                              ? BoxDecoration(
                                                  image: DecorationImage(
                                                    image: MemoryImage(capture!),
                                                    fit: BoxFit.cover,
                                                  ),
                                                )
                                              : filters.backgroundType == BackgroundType.custom
                                                  ? BoxDecoration(
                                                      image: File(filters.backgroundImage).existsSync()
                                                          ? DecorationImage(
                                                              image: FileImage(File(filters.backgroundImage)),
                                                              fit: BoxFit.cover,
                                                            )
                                                          : null,
                                                    )
                                                  : const BoxDecoration(color: Colors.transparent),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: filters.backgroundBlur,
                                          sigmaY: filters.backgroundBlur,
                                        ),
                                        child: Transform(
                                          transform: filters.skewX != 0 && filters.skewY != 0
                                              ? (Matrix4.identity()
                                                ..scaled(0.1, 0.1, 0.1)
                                                ..setEntry(3, 2, filters.skewPerspective)
                                                ..rotateX(0.1 * filters.skewY)
                                                ..rotateY(-0.1 * filters.skewX))
                                              : Matrix4.identity(),
                                          filterQuality: FilterQuality.high,
                                          alignment: Alignment.center,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.start,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              if (filters.watermark.isNotEmpty) const SizedBox(width: 20),
                                              Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                mainAxisSize: MainAxisSize.min,
                                                children: <Widget>[
                                                  if (filters.watermark.isNotEmpty) const SizedBox(height: 20),
                                                  Container(
                                                    constraints: capturing ? null : const BoxConstraints(maxHeight: 400, maxWidth: 500),
                                                    child: FittedBox(
                                                      alignment: Alignment.center,
                                                      // fit: BoxFit.fill,
                                                      child: Stack(
                                                        children: <Widget>[
                                                          Container(
                                                            decoration: BoxDecoration(
                                                              color: bgColor,
                                                              borderRadius: BorderRadius.all(Radius.circular(filters.borderRadius)),
                                                              boxShadow: filters.shadowRadius != 0 && filters.shadowSpread != 0
                                                                  ? <BoxShadow>[
                                                                      BoxShadow(
                                                                        offset: const Offset(3, 3),
                                                                        spreadRadius: filters.shadowSpread,
                                                                        blurRadius: filters.shadowRadius,
                                                                        color: const Color.fromRGBO(0, 0, 0, 0.5),
                                                                      ),
                                                                    ]
                                                                  : null,
                                                            ),
                                                            padding: EdgeInsets.all(filters.imagePadding.ceil().toDouble()),
                                                            child: GestureDetector(
                                                              onPanUpdate: (DragUpdateDetails details) => setState(() => filters
                                                                ..skewX = (filters.skewX + details.delta.dx / (photo!.width / 2))
                                                                ..skewY = (filters.skewY + details.delta.dy / (photo!.height / 2))),
                                                              onDoubleTap: () => setState(() => filters
                                                                ..skewX = 0
                                                                ..skewY = 0),
                                                              child: ClipRRect(
                                                                borderRadius: BorderRadius.circular(filters.borderRadius),
                                                                child: Image.memory(
                                                                  capture!,
                                                                  fit: BoxFit.contain,
                                                                  width: photo!.width.toDouble(),
                                                                  height: photo!.height.toDouble(),
                                                                  filterQuality: FilterQuality.high,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          Positioned(
                                                            bottom: 0,
                                                            right: 0,
                                                            child: Transform.translate(
                                                              offset: const Offset(0, 25),
                                                              child: Transform(
                                                                transform: Matrix4.skewX(-0.2),
                                                                child: Text(
                                                                  filters.watermark,
                                                                  textAlign: TextAlign.right,
                                                                  style: TextStyle(
                                                                    fontWeight: FontWeight.bold,
                                                                    fontSize: 17,
                                                                    shadows: <Shadow>[Shadow(blurRadius: 1, color: Colors.black.withOpacity(0.7))],
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          )
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  if (filters.watermark.isNotEmpty) const SizedBox(height: 20),
                                                ],
                                              ),
                                              if (filters.watermark.isNotEmpty) const SizedBox(width: 20),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )),
                        ),
                      )
              ],
            ),
          ),
        const SizedBox(height: 20),
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await WinUtils.screenCapture();
                        capture = null;
                        setState(() {});
                        loadCaptureFile();

                        setState(() {});
                      },
                      icon: const Icon(Icons.photo_camera_rounded),
                      label: const Text("Capture"),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        capturing = true;
                        setState(() {});
                        await screenshotController.captureAndSave('${WinUtils.getTabameSettingsFolder()}/fancyshot');
                        Future<void>.delayed(const Duration(milliseconds: 50), () {
                          capturing = false;
                          setState(() {});
                        });
                        WinUtils.open('${WinUtils.getTabameSettingsFolder()}/fancyshot');
                        if (globalSettings.args.contains("-fancyshot") && closeOnAction) {
                          exit(0);
                        }
                      },
                      icon: const Icon(Icons.save),
                      label: const Text("Save"),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        capturing = true;
                        setState(() {});
                        final String? filename = (await screenshotController.captureAndSave('${WinUtils.getTabameSettingsFolder()}/fancyshot'))?.replaceAll('/', r'\');
                        if (filename == null) return;
                        Future<void>.delayed(const Duration(milliseconds: 50), () async {
                          capturing = false;
                          await winClipboard.copyImageToClipboard(filename);
                          setState(() {});
                          if (globalSettings.args.contains("-fancyshot") && closeOnAction) {
                            exit(0);
                          }
                          copyMessage = "Copied!";
                          Future<void>.delayed(const Duration(seconds: 1), () => mounted ? setState(() => copyMessage = "Copy") : null);
                        });
                      },
                      icon: const Icon(Icons.copy_all),
                      label: Text(copyMessage),
                    ),
                    const SizedBox(width: 10),
                    if (globalSettings.args.contains("-fancyshot"))
                      SizedBox(
                          width: 70, child: CheckBoxWidget(onChanged: (bool e) => setState(() => closeOnAction = !closeOnAction), value: closeOnAction, text: "Exit"))
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (selectedProfile != null && selectedProfile != "Default")
                        IconButton(
                          splashRadius: 20,
                          onPressed: () {
                            profiles.removeWhere((FancyShotProfile e) => e.name == selectedProfile);
                            profilesName.removeWhere((String element) => element == selectedProfile);
                            Boxes.updateSettings("fancyShotProfile", jsonEncode(profiles));
                            selectedProfile = null;
                            if (profilesName.isEmpty) profilesName.add("");
                            setState(() {});
                          },
                          icon: const Icon(Icons.delete),
                        ),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton2<String>(
                            isExpanded: false,
                            key: UniqueKey(),
                            hint: Text(
                              "Select Profile",
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            buttonPadding: const EdgeInsets.symmetric(horizontal: 5),
                            dropdownPadding: const EdgeInsets.all(1),
                            offset: const Offset(0, 40),
                            isDense: true,
                            style: const TextStyle(fontSize: 200),
                            items: profilesName
                                .map((String item) => DropdownMenuItem<String>(value: item, child: Text(item, style: const TextStyle(fontSize: 14))))
                                .toList(),
                            value: selectedProfile,
                            onChanged: (String? value) {
                              if (value == null) return;
                              final int i = profiles.indexWhere((FancyShotProfile element) => element.name == value);
                              if (i >= 0) {
                                selectedProfile = value;
                                filters = profiles[i].copyWith();
                                watermarkTextController.text = filters.watermark;
                                skewPerspectiveController.text = filters.skewPerspective.toString();
                                Boxes.pref.setString("fancyshot", value);
                              }
                              setState(() {});
                            },
                            buttonHeight: 40,
                            buttonWidth: 200,
                            itemHeight: 30,
                            dropdownMaxHeight: 200,
                            searchController: textEditingController,
                            searchInnerWidget: Padding(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 4,
                                right: 8,
                                left: 8,
                              ),
                              child: TextFormField(
                                controller: textEditingController,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  hintText: 'Create Profile (press Enter)',
                                  hintStyle: const TextStyle(fontSize: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onFieldSubmitted: (String? newValue) {
                                  if (newValue == null) return;
                                  if (newValue.isEmpty) return;
                                  profiles.add(filters.copyWith(name: newValue));
                                  profilesName.add(newValue);
                                  if (profilesName.contains("")) profilesName.remove("");
                                  Boxes.updateSettings("fancyShotProfile", jsonEncode(profiles));
                                  Boxes.updateSettings("fancyshot", newValue);
                                  textEditingController.clear();
                                  selectedProfile = newValue;

                                  setState(() {});
                                },
                              ),
                            ),
                            searchMatchFn: (DropdownMenuItem<dynamic> item, String searchValue) {
                              return true;
                            },
                            onMenuStateChange: (bool isOpen) {
                              if (!isOpen) {
                                textEditingController.clear();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
            SliderTheme(
              data: Theme.of(context).sliderTheme.copyWith(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4, elevation: 0),
                    minThumbSeparation: 0,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 5.0),
                  ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Center(
                          child: Text("Background Padding", style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const SizedBox(height: 10),
                        Slider(
                          value: filters.backgroundPadding,
                          min: 10,
                          max: 50,
                          divisions: 20,
                          onChanged: (double e) {
                            filters.backgroundPadding = e;
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        Text("Image Padding", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Slider(
                          value: filters.imagePadding,
                          min: 00,
                          max: 50,
                          divisions: 20,
                          onChanged: (double e) {
                            filters.imagePadding = e;
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Text("Shadow Radius", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Slider(
                          value: filters.shadowRadius,
                          min: 0,
                          max: 10,
                          divisions: 20,
                          onChanged: (double e) {
                            if (filters.shadowSpread == 0) {
                              filters.shadowSpread = 1;
                            }
                            filters.shadowRadius = e;
                            if (filters.shadowRadius == 0) {
                              filters.shadowSpread = 0;
                            }
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        Text("Shadow Spread", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Slider(
                          value: filters.shadowSpread,
                          min: 0,
                          max: 10,
                          divisions: 20,
                          onChanged: (double e) {
                            if (filters.shadowRadius == 0) {
                              filters.shadowRadius = 1;
                            }
                            filters.shadowSpread = e;
                            if (filters.shadowSpread == 0) {
                              filters.shadowRadius = 0;
                            }
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Column(
                      children: <Widget>[
                        Text("Border Radius", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Slider(
                          value: filters.borderRadius,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          onChanged: (double e) {
                            filters.borderRadius = e;
                            setState(() {});
                          },
                        ),
                        Text("Background Blur", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Slider(
                          value: filters.backgroundBlur,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          onChanged: (double e) {
                            filters.backgroundBlur = e;
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          TextField(
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              hintText: "Watermark",
                              hintStyle: const TextStyle(fontSize: 12),
                              border: UnderlineInputBorder(
                                // borderSide: const BorderSide(width: 5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            controller: watermarkTextController,
                            onChanged: (String e) {
                              filters.watermark = e;
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 5),
                          MouseScrollWidget(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                OutlinedButton(
                                  onPressed: () => setState(() => filters
                                    ..skewX = 0
                                    ..skewY = 0),
                                  child: const Text("Reset Skew", style: TextStyle(height: 1.1)),
                                ),
                                Tooltip(
                                  message: "Skew Perspective",
                                  child: Container(
                                    width: 80,
                                    child: TextField(
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        hintText: "0.001",
                                        hintStyle: const TextStyle(fontSize: 12),
                                        border: UnderlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      controller: skewPerspectiveController,
                                      onChanged: (String e) {
                                        filters.skewPerspective = double.tryParse(e) ?? 0.0;
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                )
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          OutlinedButton(onPressed: () => setState(() => capturing = !capturing), child: const Text("Real View"))

                          // const Divider(height: 10, thickness: 1),
                          // MouseScrollWidget(
                          //   scrollDirection: Axis.horizontal,
                          //   child: ToggleButtons(
                          //     direction: Axis.horizontal,
                          //     onPressed: (int index) {
                          //       aspectRatio = index;
                          //       setState(() {});
                          //     },
                          //     borderRadius: const BorderRadius.all(Radius.circular(8)),
                          //     constraints: const BoxConstraints(
                          //       minHeight: 20.0,
                          //       minWidth: 35.0,
                          //     ),
                          //     isSelected: List<bool>.generate(4, (int index) => index != aspectRatio ? false : true),
                          //     children: <Widget>[
                          //       const Text("A"),
                          //       const Text("3:2"),
                          //       const Text("4:3"),
                          //       const Text("16:9"),
                          //     ],
                          //   ),
                          // ),
                          // const SizedBox(height: 5),
                          // SizedBox(
                          //   width: 200,
                          //   child: Row(
                          //     children: <Widget>[
                          //       Expanded(
                          //         child: TextInput(
                          //           labelText: "Width",
                          //           decoration: InputDecoration(
                          //             isDense: true,
                          //             contentPadding: const EdgeInsets.symmetric(
                          //               horizontal: 10,
                          //               vertical: 7,
                          //             ),
                          //             hintText: "Width",
                          //             hintStyle: const TextStyle(fontSize: 12),
                          //             border: OutlineInputBorder(
                          //               borderRadius: BorderRadius.circular(8),
                          //             ),
                          //           ),
                          //           value: filters.width == 0 ? "" : filters.width.toString(),
                          //           onChanged: (String e) {},
                          //           onUpdated: (String e) {
                          //             filters.width = (int.tryParse(e) ?? 0).abs();
                          //             setState(() {});
                          //           },
                          //         ),
                          //       ),
                          //       const SizedBox(width: 3),
                          //       Expanded(
                          //         child: TextInput(
                          //           labelText: "Height",
                          //           decoration: InputDecoration(
                          //             isDense: true,
                          //             contentPadding: const EdgeInsets.symmetric(
                          //               horizontal: 10,
                          //               vertical: 7,
                          //             ),
                          //             hintText: "Height",
                          //             hintStyle: const TextStyle(fontSize: 12),
                          //             border: OutlineInputBorder(
                          //               borderRadius: BorderRadius.circular(8),
                          //             ),
                          //           ),
                          //           value: filters.height == 0 ? "" : filters.height.toString(),
                          //           onChanged: (String e) {},
                          //           onUpdated: (String e) {
                          //             filters.height = (int.tryParse(e) ?? 0).abs();
                          //             setState(() {});
                          //           },
                          //         ),
                          //       )
                          //     ],
                          //   ),
                          // ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            MouseScrollWidget(
              // controller: ScrollController(),
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () {
                      filters.backgroundType = BackgroundType.transparent;
                      setState(() {});
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 60,
                          height: 37,
                          decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1)),
                        ),
                        const Center(
                          child: Text(
                            "Transparent",
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (capture != null)
                    InkWell(
                      onTap: () {
                        filters.backgroundType = BackgroundType.self;
                        setState(() {});
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          Container(
                            width: 60,
                            height: 37,
                            decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 1), image: DecorationImage(image: MemoryImage(capture!))),
                          ),
                          Text(
                            "Image",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, shadows: <Shadow>[Shadow(blurRadius: 1, color: Colors.black.withOpacity(0.5))]),
                          )
                        ],
                      ),
                    ),
                  InkWell(
                    onTap: () {
                      final OpenFilePicker file = OpenFilePicker()
                        ..filterSpecification = <String, String>{'PNG Image (*.png)': '*.png'}
                        ..defaultFilterIndex = 0
                        ..defaultExtension = 'png'
                        ..title = 'Select an image';

                      final File? result = file.getFile();
                      if (result == null) return;

                      filters.backgroundType = BackgroundType.custom;
                      filters.backgroundImage = result.path;
                      setState(() {});
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 60,
                          height: 37,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black, width: 1),
                            image: (filters.backgroundType == BackgroundType.custom)
                                ? DecorationImage(image: FileImage(File(filters.backgroundImage)))
                                : DecorationImage(image: AssetImage(globalSettings.logo)),
                          ),
                        ),
                        Text(
                          "Custom",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, shadows: <Shadow>[Shadow(blurRadius: 1, color: Colors.black.withOpacity(0.5))]),
                        )
                      ],
                    ),
                  ),
                  ...List<Widget>.generate(
                    10,
                    (int index) => InkWell(
                      onTap: () {
                        filters.backgroundType = BackgroundType.stock;
                        filters.backgroundImage = "resources/gradient/gradient$index.jpg";
                        setState(() {});
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                        child: Image.asset('resources/gradient/gradient$index.jpg', width: 60),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const InfoText("You can set a shortcut from Hotkeys for Fancyshot." " Even if the zoom breaks, the image will be printed good."),
      ],
    );
  }
}

enum BackgroundType {
  transparent,
  self,
  custom,
  stock,
}

class FancyShotProfile {
  String name;
  double backgroundPadding = 10;
  double imagePadding = 10;
  //enum
  BackgroundType backgroundType = BackgroundType.transparent;
  String backgroundImage = "resources/gradient/gradient1.jpg";
  double borderRadius = 10;
  double shadowSpread = 0;
  double shadowRadius = 0;
  double backgroundBlur = 0;
  double skewX = 0;
  double skewY = 0;
  double skewPerspective = 0;
  int background = 0;
  int aspectRatio = 0;
  String watermark = "";
  int width = 0;
  int height = 0;
  FancyShotProfile({
    required this.name,
    this.backgroundPadding = 10,
    this.imagePadding = 10,
    this.backgroundType = BackgroundType.transparent,
    this.backgroundImage = "resources/gradient/gradient1.jpg",
    this.borderRadius = 10,
    this.shadowSpread = 0,
    this.shadowRadius = 0,
    this.backgroundBlur = 0,
    this.skewX = 0,
    this.skewY = 0,
    this.skewPerspective = 0,
    this.background = 0,
    this.aspectRatio = 0,
    this.watermark = "",
    this.width = 0,
    this.height = 0,
  });

  FancyShotProfile copyWith({
    String? name,
    double? backgroundPadding,
    double? imagePadding,
    BackgroundType? backgroundType,
    String? backgroundImage,
    double? borderRadius,
    double? shadowSpread,
    double? shadowRadius,
    double? backgroundBlur,
    double? skewX,
    double? skewY,
    double? skewPerspective,
    int? background,
    int? aspectRatio,
    String? watermark,
    int? width,
    int? height,
  }) {
    return FancyShotProfile(
      name: name ?? this.name,
      backgroundPadding: backgroundPadding ?? this.backgroundPadding,
      imagePadding: imagePadding ?? this.imagePadding,
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      borderRadius: borderRadius ?? this.borderRadius,
      shadowSpread: shadowSpread ?? this.shadowSpread,
      shadowRadius: shadowRadius ?? this.shadowRadius,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      skewX: skewX ?? this.skewX,
      skewY: skewY ?? this.skewY,
      skewPerspective: skewPerspective ?? this.skewPerspective,
      background: background ?? this.background,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      watermark: watermark ?? this.watermark,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'backgroundPadding': backgroundPadding,
      'imagePadding': imagePadding,
      'backgroundType': backgroundType.index,
      'backgroundImage': backgroundImage,
      'borderRadius': borderRadius,
      'shadowSpread': shadowSpread,
      'shadowRadius': shadowRadius,
      'backgroundBlur': backgroundBlur,
      'skewX': skewX,
      'skewY': skewY,
      'skewPerspective': skewPerspective,
      'background': background,
      'aspectRatio': aspectRatio,
      'watermark': watermark,
      'width': width,
      'height': height,
    };
  }

  factory FancyShotProfile.fromMap(Map<String, dynamic> map) {
    return FancyShotProfile(
      name: (map['name'] ?? '') as String,
      backgroundPadding: (map['backgroundPadding'] ?? 0.0) as double,
      imagePadding: (map['imagePadding'] ?? 0.0) as double,
      backgroundType: BackgroundType.values[(map['backgroundType'] ?? 0) as int],
      backgroundImage: (map['backgroundImage'] ?? "resources/gradient/gradient1.jpg") as String,
      borderRadius: (map['borderRadius'] ?? 0.0) as double,
      shadowSpread: (map['shadowSpread'] ?? 0.0) as double,
      shadowRadius: (map['shadowRadius'] ?? 0.0) as double,
      backgroundBlur: (map['backgroundBlur'] ?? 0.0) as double,
      skewX: (map['skewX'] ?? 0.0) as double,
      skewY: (map['skewY'] ?? 0.0) as double,
      skewPerspective: (map['skewPerspective'] ?? 0.0) as double,
      background: (map['background'] ?? 0) as int,
      aspectRatio: (map['aspectRatio'] ?? 0) as int,
      watermark: (map['watermark'] ?? '') as String,
      width: (map['width'] ?? 0) as int,
      height: (map['height'] ?? 0) as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory FancyShotProfile.fromJson(String source) => FancyShotProfile.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'FancyShotProfile(name: $name, backgroundPadding: $backgroundPadding, imagePadding: $imagePadding, backgroundType: $backgroundType, backgroundImage: $backgroundImage, borderRadius: $borderRadius, shadowSpread: $shadowSpread, shadowRadius: $shadowRadius, backgroundBlur: $backgroundBlur, skewX: $skewX, skewY: $skewY, background: $background, aspectRatio: $aspectRatio, watermark: $watermark, width: $width, height: $height)';
  }

  @override
  bool operator ==(covariant FancyShotProfile other) {
    if (identical(this, other)) return true;

    return other.name == name &&
        other.backgroundPadding == backgroundPadding &&
        other.imagePadding == imagePadding &&
        other.backgroundType == backgroundType &&
        other.backgroundImage == backgroundImage &&
        other.borderRadius == borderRadius &&
        other.shadowSpread == shadowSpread &&
        other.shadowRadius == shadowRadius &&
        other.backgroundBlur == backgroundBlur &&
        other.skewX == skewX &&
        other.skewY == skewY &&
        other.skewPerspective == skewPerspective &&
        other.background == background &&
        other.aspectRatio == aspectRatio &&
        other.watermark == watermark &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        backgroundPadding.hashCode ^
        imagePadding.hashCode ^
        backgroundType.hashCode ^
        backgroundImage.hashCode ^
        borderRadius.hashCode ^
        shadowSpread.hashCode ^
        shadowRadius.hashCode ^
        backgroundBlur.hashCode ^
        skewX.hashCode ^
        skewY.hashCode ^
        skewPerspective.hashCode ^
        background.hashCode ^
        aspectRatio.hashCode ^
        watermark.hashCode ^
        width.hashCode ^
        height.hashCode;
  }
}
