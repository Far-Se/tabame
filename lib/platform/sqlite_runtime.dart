import 'dart:io';

import 'windows/windows_bootstrap.dart';

/// Shared entrypoint for preparing SQLite's native runtime.
///
/// The operation is a no-op outside Windows. The Windows-specific DLL layout
/// remains owned by [WindowsBootstrap], not by database models or `main.dart`.
class SqliteRuntime {
  SqliteRuntime._();

  static void prepare() {
    if (Platform.isWindows) WindowsBootstrap.prepareSqliteRuntime();
  }
}
