import 'dart:io';

import '../../../platform/windows/tabamewin32_api.dart' show launchWithExplorer;
import 'quicklink.dart';
import 'quicklink_template.dart';

class QuicklinkRunner {
  QuicklinkRunner._();

  static Future<void> open(Quicklink quicklink, String target, {String? openWith}) async {
    QuicklinkTemplate.validateTarget(target);
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      throw UnsupportedError('Opening quicklinks is currently available on Windows.');
    }
    String resolved = target;
    if (resolved.startsWith('~/') || resolved.startsWith('~\\')) {
      final String? profile = Platform.environment['USERPROFILE'];
      if (profile == null) throw const FileSystemException('Could not find your home folder.');
      resolved = '$profile\\${resolved.substring(2)}';
    } else if (resolved.toLowerCase().startsWith('file:')) {
      resolved = Uri.parse(resolved).toFilePath(windows: true);
    }
    if (QuicklinkTemplate.isLocalPath(resolved) &&
        FileSystemEntity.typeSync(resolved) == FileSystemEntityType.notFound) {
      throw FileSystemException('The file or folder does not exist', resolved);
    }
    final String application = (openWith ?? quicklink.openWith).trim();
    // Pass a single Windows argv value, never parse the target as a command.
    final bool opened = await launchWithExplorer(application.isEmpty ? resolved : application,
        arguments: application.isEmpty ? null : quoteWindowsArgument(resolved));
    if (!opened)
      throw FileSystemException(
          'Windows could not open this quicklink. Check the link and Open With application.', resolved);
  }

  static String quoteWindowsArgument(String value) {
    final StringBuffer result = StringBuffer('"');
    int backslashes = 0;
    for (final int unit in value.codeUnits) {
      if (unit == 92) {
        backslashes++;
        continue;
      }
      if (unit == 34) {
        result.write('\\' * (backslashes * 2 + 1));
      } else {
        result.write('\\' * backslashes);
      }
      result.writeCharCode(unit);
      backslashes = 0;
    }
    result.write('\\' * (backslashes * 2));
    result.write('"');
    return result.toString();
  }
}
