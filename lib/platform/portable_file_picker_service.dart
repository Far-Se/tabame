import 'dart:io';

import 'file_picker_service.dart';

/// File picker implementation for the Phase 4 portable shell.
///
/// It uses the host desktop's existing chooser command rather than a custom
/// native plugin: AppleScript/LaunchServices on macOS, and zenity/kdialog on
/// Linux. Missing desktop helpers report an unavailable result.
class PortableFilePickerService extends FilePickerService {
  const PortableFilePickerService();

  static bool _linuxChooserChecked = false;
  static String? _linuxChooserExecutable;

  @override
  bool get isAvailable {
    if (Platform.isMacOS) return true;
    if (!Platform.isLinux) return false;
    return _linuxChooser() != null;
  }

  @override
  String get unavailableReason {
    if (isAvailable) return '';
    if (Platform.isLinux) return 'No zenity or kdialog file picker is installed on this Linux desktop.';
    return 'A portable file picker is unavailable on this platform.';
  }

  @override
  File? openFile(OpenFilePicker request) => null;

  @override
  List<File> openFiles(OpenFilePicker request) => <File>[];

  @override
  Directory? pickDirectory(DirectoryPicker request) => null;

  @override
  File? saveFile(SaveFilePicker request) => null;

  @override
  Future<File?> pickFile(OpenFilePicker request) async {
    final String? path = await _chooseFile(request);
    return path == null || path.isEmpty ? null : File(path);
  }

  @override
  Future<List<File>> pickFiles(OpenFilePicker request) async {
    final File? file = await pickFile(request);
    return file == null ? <File>[] : <File>[file];
  }

  @override
  Future<Directory?> pickDirectoryAsync(DirectoryPicker request) async {
    final String? path = await _chooseDirectory(request);
    return path == null || path.isEmpty ? null : Directory(path);
  }

  @override
  Future<File?> pickSaveFile(SaveFilePicker request) async {
    final String? path = await _chooseSaveFile(request);
    return path == null || path.isEmpty ? null : File(path);
  }

  Future<String?> _chooseFile(OpenFilePicker request) async {
    if (Platform.isMacOS) {
      final String title = _escapeAppleScript(request.title.isEmpty ? 'Select a file' : request.title);
      return _runProcess('/usr/bin/osascript', <String>['-e', 'POSIX path of (choose file with prompt "$title")']);
    }
    return _runLinuxChooser(<String>['--file-selection', if (request.title.isNotEmpty) '--title=${request.title}']);
  }

  Future<String?> _chooseDirectory(DirectoryPicker request) async {
    if (Platform.isMacOS) {
      final String title = _escapeAppleScript(request.title.isEmpty ? 'Select a folder' : request.title);
      return _runProcess('/usr/bin/osascript', <String>['-e', 'POSIX path of (choose folder with prompt "$title")']);
    }
    return _runLinuxChooser(
        <String>['--file-selection', '--directory', if (request.title.isNotEmpty) '--title=${request.title}']);
  }

  Future<String?> _chooseSaveFile(SaveFilePicker request) async {
    if (Platform.isMacOS) {
      final String title = _escapeAppleScript(request.title.isEmpty ? 'Save file' : request.title);
      final String name = _escapeAppleScript(request.fileName);
      return _runProcess('/usr/bin/osascript', <String>[
        '-e',
        'POSIX path of (choose file name with prompt "$title"${name.isEmpty ? '' : ' default name "$name"'})',
      ]);
    }
    return _runLinuxChooser(<String>[
      '--file-selection',
      '--save',
      if (request.title.isNotEmpty) '--title=${request.title}',
      if (request.fileName.isNotEmpty) '--filename=${request.fileName}',
    ]);
  }

  Future<String?> _runLinuxChooser(List<String> arguments) async {
    final String? availableChooser = _linuxChooser();
    final Iterable<String> executables = availableChooser == null ? const <String>[] : <String>[availableChooser];
    for (final String executable in executables) {
      try {
        final List<String> actualArguments = executable == 'kdialog' ? _kdialogArguments(arguments) : arguments;
        final ProcessResult result = await Process.run(executable, actualArguments);
        if (result.exitCode == 0) {
          final String output = '${result.stdout}'.trim();
          if (output.isNotEmpty) return output.split('\n').first.trim();
        }
        // A launched chooser returning non-zero means cancellation or an
        // actual chooser error. Do not surprise the user with a second dialog.
        return null;
      } on ProcessException {
        // This helper is missing; try the next desktop chooser.
      }
    }
    return null;
  }

  String? _linuxChooser() {
    if (_linuxChooserChecked) return _linuxChooserExecutable;
    _linuxChooserChecked = true;
    for (final String executable in <String>['zenity', 'kdialog']) {
      try {
        final ProcessResult result = Process.runSync(
          'sh',
          <String>['-c', 'command -v "$executable"'],
          runInShell: false,
        );
        if (result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty) {
          _linuxChooserExecutable = executable;
          return executable;
        }
      } on Object {
        // Continue checking the alternate helper.
      }
    }
    return null;
  }

  List<String> _kdialogArguments(List<String> arguments) {
    final bool directory = arguments.contains('--directory');
    final bool save = arguments.contains('--save');
    if (directory) return <String>['--getexistingdirectory'];
    if (save) return <String>['--getsavefilename'];
    return <String>['--getopenfilename'];
  }

  Future<String?> _runProcess(String executable, List<String> arguments) async {
    try {
      final ProcessResult result = await Process.run(executable, arguments);
      if (result.exitCode != 0) return null;
      return '${result.stdout}'.trim();
    } on ProcessException {
      return null;
    }
  }

  String _escapeAppleScript(String value) => value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
}
