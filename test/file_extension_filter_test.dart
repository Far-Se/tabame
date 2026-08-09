import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/classes/boxes/search_folder_box.dart';
import 'package:tabame/models/util/file_extension_filter.dart';

void main() {
  group('file extension filter', () {
    test('normalizes space, comma, semicolon, and newline separated input', () {
      expect(
        parseFileExtensions('.BIN dat;DLL\n.sha256 .bin'),
        <String>['.bin', '.dat', '.dll', '.sha256'],
      );
    });

    test('includes only matching extensions in allow mode', () {
      final Set<String> extensions = normalizeFileExtensions(<String>['exe', '.lnk']);

      expect(includesFileExtension('Tabame.EXE', extensions, excludeMatches: false), isTrue);
      expect(includesFileExtension('notes.txt', extensions, excludeMatches: false), isFalse);
    });

    test('skips matching extensions in exclude mode', () {
      final Set<String> extensions = normalizeFileExtensions(<String>['.bin', '.dat', '.dll', '.sha256']);

      expect(includesFileExtension('payload.BIN', extensions, excludeMatches: true), isFalse);
      expect(includesFileExtension('notes.txt', extensions, excludeMatches: true), isTrue);
      expect(includesFileExtension('.gitignore', extensions, excludeMatches: true), isTrue);
    });

    test('does not filter files when the extension list is empty', () {
      expect(includesFileExtension('anything.bin', <String>{}, excludeMatches: false), isTrue);
      expect(includesFileExtension('anything.bin', <String>{}, excludeMatches: true), isTrue);
    });
  });

  group('SearchFolder extension mode', () {
    test('loads existing settings in allow mode', () {
      final SearchFolder folder = SearchFolder.fromMap(<String, dynamic>{
        'path': r'C:\Tools',
        'includeFolders': true,
        'includeFiles': true,
        'allowedExtensions': <String>['.exe'],
      });

      expect(folder.excludeExtensions, isFalse);
    });

    test('persists exclude mode and includes it in equality', () {
      final SearchFolder folder = SearchFolder(
        path: r'C:\Files',
        allowedExtensions: const <String>['.bin'],
        excludeExtensions: true,
      );
      final SearchFolder restored = SearchFolder.fromJson(folder.toJson());

      expect(restored, folder);
      expect(restored.excludeExtensions, isTrue);
      expect(folder.copyWith(excludeExtensions: false), isNot(folder));
    });
  });
}
