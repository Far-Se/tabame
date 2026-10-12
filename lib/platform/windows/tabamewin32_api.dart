// Windows-only facade for Tabame's native plugin.
//
// The native provider remains Windows-specific. Keeping its package import in
// this adapter makes the dependency boundary explicit without changing the
// existing Windows method-channel behavior.
import 'package:path/path.dart' as p;
import 'package:tabamewin32/tabamewin32.dart' as native;

import '../app_paths.dart';

export 'package:tabamewin32/tabamewin32.dart' hide launchWithExplorer, nativeShellOpen;

/// Resolve paths inside the package before Explorer receives them outside it.
Future<bool> launchWithExplorer(String file, {String? arguments, String workingDirectory = ''}) {
  return native.launchWithExplorer(
    AppPaths.externalPath(file),
    arguments: _externalExplorerArguments(file, arguments),
    workingDirectory: AppPaths.externalPath(workingDirectory),
  );
}

Future<void> nativeShellOpen(String path, {String arguments = '', String workingDirectory = ''}) {
  return native.nativeShellOpen(
    AppPaths.externalPath(path),
    arguments: _externalExplorerArguments(path, arguments) ?? '',
    workingDirectory: AppPaths.externalPath(workingDirectory),
  );
}

String? _externalExplorerArguments(String executable, String? arguments) {
  if (arguments == null || arguments.isEmpty || !AppPaths.isPackagedInstall) return arguments;
  final String name = p.windows.basename(executable).toLowerCase();
  if (name != 'explorer' && name != 'explorer.exe') return arguments;

  // Keep switches and quoting intact, including /select,"C:\path with spaces".
  if (arguments.contains('"')) {
    return arguments.replaceAllMapped(RegExp(r'"([^"]*)"'), (Match match) {
      return '"${AppPaths.externalPath(match.group(1)!)}"';
    });
  }
  final RegExpMatch? selection = RegExp(r'^(/select,)(.*)$', caseSensitive: false).firstMatch(arguments);
  if (selection != null) {
    return '${selection.group(1)}"${AppPaths.externalPath(selection.group(2)!)}"';
  }
  final String resolved = AppPaths.externalPath(arguments);
  return resolved == arguments ? arguments : '"$resolved"';
}
