/// Shared entrypoint for preparing SQLite's native runtime.
///
/// SQLite is packaged beside the executable before launch. Runtime code never
/// writes or renames DLLs in the installed executable directory.
class SqliteRuntime {
  SqliteRuntime._();

  static void prepare() {}
}
