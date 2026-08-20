## Dart validation

After editing Dart files, from the project root, using `dart` as resolved from PATH:

```
dart format <changed-files>
dart analyze <changed-files>
```

**Never:** invoke `dart.bat`/`flutter.bat` (even via absolute path), invoke Dart by absolute path, modify/reconstruct PATH, use the Dart MCP `dart_format` tool, or run `flutter build`/`flutter run`.
**Never run** any building commands like `flutter build windows` if you havent changed CPP/H code.
**Never run** `flutter test` or any form of tests.
If you modified some code that has a `_test.dart` file, only run that.

**Rules:** one Dart command at a time; format/analyze only files changed this task; run format once and analyze once (no full-project analysis unless asked); on failure, report the command, the failure, and any output as-is.

## Native Feature Implementation

Only implement code for Windows if you need native API/functions and leave a mockup for Linux and Mac with comment `//TODO: Implement multiplatform`
