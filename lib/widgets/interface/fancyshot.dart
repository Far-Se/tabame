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
  final List<FancyShotProfile> profiles = Boxes.getSavedMap<FancyShotProfile>(FancyShotProfile.fromJson, "fancyShotProfile");
  final List<String> profilesName = <String>[""];
  int aspectRatio = 0;
  String? selectedProfile;
  final TextEditingController textEditingController = TextEditingController();

  bool capturing = false;

  TextEditingController watermarkTextController = TextEditingController();

  bool closeOnAction = true;

  String copyMessage = "Copy";
  final WinClipboard winClipboard = WinClipboard();
  @override
  void initState() {
    super.initState();
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
    }

    if (profilesName.length > 1) profilesName.remove("");
    loadCaptureFile();
  }

  @override
  void dispose() {
    textEditingController.dispose();
    watermarkTextController.dispose();
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
                        child: MouseScrollWidget(
                          scrollDirection: Axis.horizontal,
                          child: MouseScrollWidget(
                            scrollDirection: Axis.vertical,
                            child: FancyShotView(screenshotController: screenshotController, filters: filters, capture: capture, capturing: capturing, bgColor: bgColor),
                          ),
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
                        Future<void>.delayed(const Duration(milliseconds: 30), () {
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
                        Future<void>.delayed(const Duration(milliseconds: 30), () {
                          capturing = false;
                          winClipboard.copyImageToClipboard(filename);
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
                                .map((String item) => DropdownMenuItem<String>(
                                      value: item,
                                      child: Text(
                                        item,
                                        style: const TextStyle(
                                          fontSize: 14,
                                        ),
                                      ),
                                    ))
                                .toList(),
                            value: selectedProfile,
                            onChanged: (String? value) {
                              if (value == null) return;
                              final int i = profiles.indexWhere((FancyShotProfile element) => element.name == value);
                              if (i >= 0) {
                                selectedProfile = value;
                                filters = profiles[i].copyWith();
                                watermarkTextController.text = filters.watermark;
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
                                  profiles.add(FancyShotProfile(
                                    name: newValue,
                                    backgroundPadding: filters.backgroundPadding,
                                    imagePadding: filters.imagePadding,
                                    backgroundType: filters.backgroundType,
                                    backgroundImage: filters.backgroundImage,
                                    borderRadius: filters.borderRadius,
                                    shadowSpread: filters.shadowSpread,
                                    shadowRadius: filters.shadowRadius,
                                    backgroundBlur: filters.backgroundBlur,
                                    background: filters.background,
                                    aspectRatio: filters.aspectRatio,
                                    watermark: filters.watermark,
                                    width: filters.width,
                                    height: filters.height,
                                  ));
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

class FancyShotView extends StatefulWidget {
  const FancyShotView({
    Key? key,
    required this.screenshotController,
    required this.filters,
    required this.capture,
    required this.capturing,
    required this.bgColor,
  }) : super(key: key);

  final ScreenshotController screenshotController;
  final FancyShotProfile filters;
  final Uint8List? capture;
  final bool capturing;
  final Color? bgColor;

  @override
  State<FancyShotView> createState() => _FancyShotViewState();
}

class _FancyShotViewState extends State<FancyShotView> {
  @override
  void initState() {
    super.initState();
    initializeGDI();
  }

  @override
  Widget build(BuildContext context) {
    return Screenshot<Widget>(
      controller: widget.screenshotController,
      child: Material(
        type: MaterialType.transparency,
        child: ClipRect(
          child: Container(
            padding: EdgeInsets.all(widget.filters.backgroundPadding),
            decoration: widget.filters.backgroundType == BackgroundType.stock
                ? BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage(widget.filters.backgroundImage),
                      fit: BoxFit.cover,
                    ),
                  )
                : widget.filters.backgroundType == BackgroundType.self
                    ? BoxDecoration(
                        image: DecorationImage(
                          image: MemoryImage(widget.capture!),
                          fit: BoxFit.cover,
                        ),
                      )
                    : widget.filters.backgroundType == BackgroundType.custom
                        ? BoxDecoration(
                            image: File(widget.filters.backgroundImage).existsSync()
                                ? DecorationImage(
                                    image: FileImage(File(widget.filters.backgroundImage)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          )
                        : const BoxDecoration(color: Colors.transparent),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: widget.filters.backgroundBlur,
                sigmaY: widget.filters.backgroundBlur,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.filters.watermark.isNotEmpty) const SizedBox(width: 20),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (widget.filters.watermark.isNotEmpty) const SizedBox(height: 20),
                      Container(
                        constraints: widget.capturing ? null : const BoxConstraints(maxHeight: 400, maxWidth: 500),
                        child: Stack(
                          children: <Widget>[
                            Container(
                              decoration: BoxDecoration(
                                color: widget.bgColor,
                                borderRadius: BorderRadius.all(Radius.circular(widget.filters.borderRadius)),
                                boxShadow: widget.filters.shadowRadius != 0 && widget.filters.shadowSpread != 0
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          offset: const Offset(3, 3),
                                          spreadRadius: widget.filters.shadowSpread,
                                          blurRadius: widget.filters.shadowRadius,
                                          color: const Color.fromRGBO(0, 0, 0, 0.5),
                                        ),
                                      ]
                                    : null,
                              ),
                              padding: EdgeInsets.all(widget.filters.imagePadding),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(widget.filters.borderRadius),
                                child: widget.filters.width != 0 && widget.filters.height != 0
                                    ? Image.memory(
                                        widget.capture!,
                                        fit: BoxFit.cover,
                                        width: widget.filters.width.toDouble() -
                                            (widget.filters.backgroundPadding * 2 + widget.filters.imagePadding * 2 + (widget.filters.watermark.isNotEmpty ? 20 * 2 : 0)),
                                        height: widget.filters.height.toDouble() -
                                            (widget.filters.backgroundPadding * 2 + widget.filters.imagePadding * 2 + (widget.filters.watermark.isNotEmpty ? 20 * 2 : 0)),
                                      )
                                    : Image.memory(widget.capture!, fit: BoxFit.contain),
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
                                    widget.filters.watermark,
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
                      if (widget.filters.watermark.isNotEmpty) const SizedBox(height: 20),
                    ],
                  ),
                  if (widget.filters.watermark.isNotEmpty) const SizedBox(width: 20),
                ],
              ),
            ),
          ),
        ),
      ),
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
  int background = 0;
  int aspectRatio = 0;
  String watermark = "";
  int width = 0;
  int height = 0;
  FancyShotProfile({
    required this.name,
    required this.backgroundPadding,
    required this.imagePadding,
    required this.backgroundType,
    required this.backgroundImage,
    required this.borderRadius,
    required this.shadowSpread,
    required this.shadowRadius,
    required this.backgroundBlur,
    required this.background,
    required this.aspectRatio,
    required this.watermark,
    required this.width,
    required this.height,
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
      backgroundImage: (map['backgroundImage'] ?? '') as String,
      borderRadius: (map['borderRadius'] ?? 0.0) as double,
      shadowSpread: (map['shadowSpread'] ?? 0.0) as double,
      shadowRadius: (map['shadowRadius'] ?? 0.0) as double,
      backgroundBlur: (map['backgroundBlur'] ?? 0.0) as double,
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
    return 'FancyShotProfile(name: $name, backgroundPadding: $backgroundPadding, imagePadding: $imagePadding, backgroundType: $backgroundType, backgroundImage: $backgroundImage, borderRadius: $borderRadius, shadowSpread: $shadowSpread, shadowRadius: $shadowRadius, backgroundBlur: $backgroundBlur, background: $background, aspectRatio: $aspectRatio, watermark: $watermark, width: $width, height: $height)';
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
        background.hashCode ^
        aspectRatio.hashCode ^
        watermark.hashCode ^
        width.hashCode ^
        height.hashCode;
  }
}
