import 'dart:io';

/// Platform-neutral file and folder picker boundary.
///
/// The request objects intentionally retain the options used by the existing
/// Windows picker call sites. A platform implementation may ignore options it
/// cannot represent, but it must return an unavailable result rather than
/// invoking a Windows method channel on another target.
abstract class FilePickerService {
  static FilePickerService _instance = const UnavailableFilePickerService();

  static FilePickerService get instance => _instance;

  static void register(FilePickerService service) {
    _instance = service;
  }

  const FilePickerService();

  bool get isAvailable;
  String get unavailableReason;

  File? openFile(OpenFilePicker request);
  List<File> openFiles(OpenFilePicker request);
  Directory? pickDirectory(DirectoryPicker request);
  File? saveFile(SaveFilePicker request);

  Future<File?> pickFile(OpenFilePicker request);
  Future<List<File>> pickFiles(OpenFilePicker request);
  Future<Directory?> pickDirectoryAsync(DirectoryPicker request);
  Future<File?> pickSaveFile(SaveFilePicker request);
}

/// Safe result provider used before a platform adapter is registered and on
/// targets without a picker implementation yet.
class UnavailableFilePickerService extends FilePickerService {
  const UnavailableFilePickerService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'File picking is unavailable on this platform.';

  @override
  File? openFile(OpenFilePicker request) => null;

  @override
  List<File> openFiles(OpenFilePicker request) => <File>[];

  @override
  Directory? pickDirectory(DirectoryPicker request) => null;

  @override
  File? saveFile(SaveFilePicker request) => null;

  @override
  Future<File?> pickFile(OpenFilePicker request) async => null;

  @override
  Future<List<File>> pickFiles(OpenFilePicker request) async => <File>[];

  @override
  Future<Directory?> pickDirectoryAsync(DirectoryPicker request) async => null;

  @override
  Future<File?> pickSaveFile(SaveFilePicker request) async => null;
}

/// File-picker request compatibility object retained for existing call sites.
class OpenFilePicker {
  String title = '';
  Map<String, String> filterSpecification = <String, String>{};
  int defaultFilterIndex = 0;
  String defaultExtension = '';
  String? initialDirectory;
  bool alwaysShowInitialDirectory = false;

  File? getFile() => FilePickerService.instance.openFile(this);

  List<File> getFiles() => FilePickerService.instance.openFiles(this);

  Future<File?> getFileAsync() => FilePickerService.instance.pickFile(this);

  Future<List<File>> getFilesAsync() => FilePickerService.instance.pickFiles(this);
}

/// Folder-picker request compatibility object retained for existing call sites.
class DirectoryPicker {
  String title = '';
  String? initialDirectory;
  bool alwaysShowInitialDirectory = false;

  Directory? getDirectory() => FilePickerService.instance.pickDirectory(this);

  Future<Directory?> getDirectoryAsync() => FilePickerService.instance.pickDirectoryAsync(this);
}

/// Save-picker request compatibility object retained for existing call sites.
class SaveFilePicker {
  String title = '';
  Map<String, String> filterSpecification = <String, String>{};
  int defaultFilterIndex = 0;
  String defaultExtension = '';
  String fileName = '';
  String? initialDirectory;
  bool alwaysShowInitialDirectory = false;

  File? getFile() => FilePickerService.instance.saveFile(this);

  Future<File?> getFileAsync() => FilePickerService.instance.pickSaveFile(this);
}
