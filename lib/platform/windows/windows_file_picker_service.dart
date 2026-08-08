import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart' as native;

import '../file_picker_service.dart';

/// Windows implementation of the shared picker boundary.
class WindowsFilePickerService extends FilePickerService {
  const WindowsFilePickerService();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  String get unavailableReason => isAvailable ? '' : 'The Windows file picker is unavailable on this platform.';

  @override
  File? openFile(OpenFilePicker request) {
    if (!isAvailable) return null;
    final native.OpenFilePicker picker = native.OpenFilePicker()
      ..title = request.title
      ..filterSpecification = request.filterSpecification
      ..defaultFilterIndex = request.defaultFilterIndex
      ..defaultExtension = request.defaultExtension;
    if (request.initialDirectory != null) picker.initialDirectory = request.initialDirectory!;
    picker.alwaysShowInitialDirectory = request.alwaysShowInitialDirectory;
    return picker.getFile();
  }

  @override
  List<File> openFiles(OpenFilePicker request) {
    if (!isAvailable) return <File>[];
    final native.OpenFilePicker picker = native.OpenFilePicker()
      ..title = request.title
      ..filterSpecification = request.filterSpecification
      ..defaultFilterIndex = request.defaultFilterIndex
      ..defaultExtension = request.defaultExtension;
    if (request.initialDirectory != null) picker.initialDirectory = request.initialDirectory!;
    picker.alwaysShowInitialDirectory = request.alwaysShowInitialDirectory;
    return picker.getFiles();
  }

  @override
  Directory? pickDirectory(DirectoryPicker request) {
    if (!isAvailable) return null;
    final native.DirectoryPicker picker = native.DirectoryPicker()..title = request.title;
    if (request.initialDirectory != null) picker.initialDirectory = request.initialDirectory!;
    picker.alwaysShowInitialDirectory = request.alwaysShowInitialDirectory;
    return picker.getDirectory();
  }

  @override
  File? saveFile(SaveFilePicker request) {
    if (!isAvailable) return null;
    final native.SaveFilePicker picker = native.SaveFilePicker()
      ..title = request.title
      ..filterSpecification = request.filterSpecification
      ..defaultFilterIndex = request.defaultFilterIndex
      ..defaultExtension = request.defaultExtension
      ..fileName = request.fileName;
    if (request.initialDirectory != null) picker.initialDirectory = request.initialDirectory!;
    picker.alwaysShowInitialDirectory = request.alwaysShowInitialDirectory;
    return picker.getFile();
  }

  @override
  Future<File?> pickFile(OpenFilePicker request) async => openFile(request);

  @override
  Future<List<File>> pickFiles(OpenFilePicker request) async => openFiles(request);

  @override
  Future<Directory?> pickDirectoryAsync(DirectoryPicker request) async => pickDirectory(request);

  @override
  Future<File?> pickSaveFile(SaveFilePicker request) async => saveFile(request);
}
