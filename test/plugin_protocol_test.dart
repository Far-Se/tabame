import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/pages/launcher/plugins/plugin_protocol.dart';

void main() {
  group('parsePluginColor', () {
    test('parses #RGB, #RRGGBB and #AARRGGBB', () {
      expect(parsePluginColor('#F80'), const Color(0xFFFF8800));
      expect(parsePluginColor('#FF8800'), const Color(0xFFFF8800));
      expect(parsePluginColor('#80FF8800'), const Color(0x80FF8800));
      expect(parsePluginColor(' #ff8800 '), const Color(0xFFFF8800));
    });

    test('rejects everything else', () {
      expect(parsePluginColor('FF8800'), isNull);
      expect(parsePluginColor('#GGHHII'), isNull);
      expect(parsePluginColor('#FF88'), isNull);
      expect(parsePluginColor('star'), isNull);
      expect(parsePluginColor(null), isNull);
      expect(parsePluginColor(42), isNull);
    });

    test('pluginColorToHex round-trips with parsePluginColor', () {
      expect(pluginColorToHex(const Color(0xFF63A0EA)), '#63A0EA');
      expect(pluginColorToHex(const Color(0xFF000001)), '#000001');
      expect(parsePluginColor(pluginColorToHex(const Color(0xFF8250DF))), const Color(0xFF8250DF));
    });
  });

  group('PluginItem visuals', () {
    test('parses tinted accessories, tileColor, section, progress, lines', () {
      final PluginItem item = PluginItem.fromJson(<String, dynamic>{
        'id': 'x',
        'title': 'X',
        'accessories': <Object?>[
          <String, Object?>{'text': 'In Progress', 'color': '#8250DF', 'icon': 'clock'},
          'plain',
        ],
        'tileColor': '#0EA5E9',
        'section': ' Today ',
        'progress': 1.7,
        'lines': 2,
      }, 0);
      expect(item.accessories, hasLength(2));
      expect(item.accessories.first.color, const Color(0xFF8250DF));
      expect(item.accessories.first.icon, 'clock');
      expect(item.accessories.last.color, isNull);
      expect(item.tileColor, const Color(0xFF0EA5E9));
      expect(item.section, 'Today');
      expect(item.progress, 1.0); // clamped
      expect(item.subtitleLines, 2);
    });

    test('parses preview metadata with images, widths, and actions', () {
      final PluginItem item = PluginItem.fromJson(<String, dynamic>{
        'id': 'x',
        'preview': <String, Object?>{
          'markdown': '# hi',
          'image': <String, Object?>{'url': 'https://example.com/cover.jpg', 'width': 180},
          'metadata': <Object?>[
            <String, Object?>{'label': 'Status', 'text': 'Open', 'color': '#00FF00'},
            <String, Object?>{'separator': true},
            <String, Object?>{'label': 'Docs', 'text': 'site', 'url': 'https://x.dev'},
            <String, Object?>{'label': 'Trend', 'sparkline': <num>[1, 2, 3]},
            <String, Object?>{
              'label': 'Poster',
              'text': 'Poster Name',
              'image': 'https://example.com/poster.webp',
              'width': 180,
              'actions': <Object?>[<String, Object?>{'id': 'open', 'title': 'Open', 'icon': 'open'}],
            },
            <String, Object?>{'label': 'invalid image', 'text': 'Text remains', 'image': 'file:///poster.png'},
            <String, Object?>{'label': 'bad entry'},
            <String, Object?>{'label': 'too short', 'sparkline': <num>[1]},
          ],
        },
      }, 0);
      expect(item.previewMarkdown, '# hi');
      expect(item.previewImageUrl, 'https://example.com/cover.jpg');
      expect(item.previewImageWidth, 180);
      // Bad entries (no text, sparkline < 2 points) are dropped.
      expect(item.previewMetadata, hasLength(6));
      expect(item.previewMetadata[1].separator, isTrue);
      expect(item.previewMetadata[2].url, 'https://x.dev');
      expect(item.previewMetadata[3].sparkline, <double>[1, 2, 3]);
      expect(item.previewMetadata[4].image, 'https://example.com/poster.webp');
      expect(item.previewMetadata[4].imageWidth, 180);
      expect(item.previewMetadata[4].actions.single.id, 'open');
      expect(item.previewMetadata[5].image, isNull);
    });
  });

  group('PluginForm', () {
    test('parses fields with defaults and drops invalid ones', () {
      final PluginRenderFrame frame = PluginRenderFrame.fromJson(<String, dynamic>{
        'type': 'render',
        'view': 'form',
        'form': <String, Object?>{
          'title': 'New Issue',
          'fields': <Object?>[
            <String, Object?>{'id': 'title', 'type': 'text', 'placeholder': 'Summary'},
            <String, Object?>{'id': 'team', 'type': 'dropdown', 'options': <Object?>['eng', <String, Object?>{'value': 'ops', 'label': 'Operations'}]},
            <String, Object?>{'id': 'urgent', 'type': 'checkbox', 'label': 'Urgent', 'value': true},
            <String, Object?>{'id': 'weird', 'type': 'teleport'},
            <String, Object?>{'type': 'text'}, // no id → dropped
          ],
        },
      });
      expect(frame.view, PluginViewType.form);
      final PluginForm form = frame.form!;
      expect(form.title, 'New Issue');
      expect(form.submitLabel, 'Submit');
      expect(form.fields, hasLength(4));
      expect(form.fields[0].label, 'title'); // label falls back to id
      expect(form.fields[1].options, hasLength(2));
      expect(form.fields[1].options.first.label, 'eng');
      expect(form.fields[1].options.last.label, 'Operations');
      expect(form.fields[2].value, true);
      expect(form.fields[3].type, 'text'); // unknown type falls back to text
    });

    test('a form view without usable fields yields no form', () {
      final PluginRenderFrame frame = PluginRenderFrame.fromJson(<String, dynamic>{
        'type': 'render',
        'view': 'form',
        'form': <String, Object?>{'fields': <Object?>[]},
      });
      expect(frame.form, isNull);
    });
  });

  group('PluginRenderFrame extras', () {
    test('parses determinate loading, placeholder, and empty state', () {
      final PluginRenderFrame frame = PluginRenderFrame.fromJson(<String, dynamic>{
        'type': 'render',
        'loading': <String, Object?>{'progress': 0.4},
        'placeholder': 'Search issues…',
        'empty': <String, Object?>{'icon': 'cloud', 'title': 'No issues', 'hint': 'Try a different filter'},
        'detail': <String, Object?>{
          'markdown': 'body',
          'metadata': <Object?>[
            <String, Object?>{'label': 'A', 'text': 'B'},
          ],
        },
      });
      expect(frame.loading, isTrue);
      expect(frame.loadingProgress, 0.4);
      expect(frame.placeholder, 'Search issues…');
      expect(frame.empty!.title, 'No issues');
      expect(frame.empty!.hint, 'Try a different filter');
      expect(frame.detailMetadata, hasLength(1));
    });

    test('boolean loading stays indeterminate and blank placeholder is dropped', () {
      final PluginRenderFrame frame = PluginRenderFrame.fromJson(<String, dynamic>{
        'type': 'render',
        'loading': true,
        'placeholder': '  ',
      });
      expect(frame.loading, isTrue);
      expect(frame.loadingProgress, isNull);
      expect(frame.placeholder, isNull);
    });

    test('detail.wide drives wantsWideWindow, like preview does', () {
      final PluginRenderFrame wide = PluginRenderFrame.fromJson(<String, dynamic>{
        'type': 'render',
        'view': 'detail',
        'detail': <String, Object?>{'markdown': '# hi', 'wide': true},
      });
      expect(wide.detailWide, isTrue);
      expect(wide.wantsWideWindow, isTrue);

      final PluginRenderFrame narrow = PluginRenderFrame.fromJson(<String, dynamic>{
        'type': 'render',
        'view': 'detail',
        'detail': '# hi',
      });
      expect(narrow.detailWide, isFalse);
      expect(narrow.wantsWideWindow, isFalse);

      // wide only counts for detail view; a list frame ignores it.
      final PluginRenderFrame list = PluginRenderFrame.fromJson(<String, dynamic>{
        'type': 'render',
        'view': 'list',
        'detail': <String, Object?>{'wide': true},
        'preview': true,
      });
      expect(list.wantsWideWindow, isTrue); // from preview, not detail.wide
    });

    test('parses canGoBack, defaulting to false', () {
      expect(
        PluginRenderFrame.fromJson(<String, dynamic>{'type': 'render', 'canGoBack': true}).canGoBack,
        isTrue,
      );
      expect(PluginRenderFrame.fromJson(<String, dynamic>{'type': 'render'}).canGoBack, isFalse);
    });
  });

  group('setQuery command', () {
    test('is a known command and carries text', () {
      final PluginCommand command = PluginCommand.fromJson(<String, dynamic>{
        'command': 'setQuery',
        'text': 'rome',
      })!;
      expect(command.name, 'setquery');
      expect(PluginCommand.knownCommands.contains(command.name), isTrue);
      expect(command.text, 'rome');
    });
  });

  group('PluginCommand', () {
    test('parses the documented command shapes', () {
      final PluginCommand copy = PluginCommand.fromJson(<String, dynamic>{
        'type': 'command',
        'command': 'copy',
        'text': '#FF8800',
      })!;
      expect(copy.name, 'copy');
      expect(copy.text, '#FF8800');
      expect(copy.url, isNull);

      final PluginCommand open = PluginCommand.fromJson(<String, dynamic>{
        'type': 'command',
        'command': 'open',
        'url': 'https://example.com',
      })!;
      expect(open.name, 'open');
      expect(open.url, 'https://example.com');

      final PluginCommand hide = PluginCommand.fromJson(<String, dynamic>{
        'type': 'command',
        'command': 'hide',
      })!;
      expect(hide.name, 'hide');
      expect(hide.text, isNull);
    });

    test('accepts "path" as an alias for "url" and normalizes the name', () {
      final PluginCommand command = PluginCommand.fromJson(<String, dynamic>{
        'command': ' Open ',
        'path': r'C:\Users\me\notes.txt',
      })!;
      expect(command.name, 'open');
      expect(command.url, r'C:\Users\me\notes.txt');
      expect(PluginCommand.knownCommands.contains(command.name), isTrue);
    });

    test('rejects messages without a usable command name', () {
      expect(PluginCommand.fromJson(<String, dynamic>{'type': 'command'}), isNull);
      expect(PluginCommand.fromJson(<String, dynamic>{'command': ''}), isNull);
      expect(PluginCommand.fromJson(<String, dynamic>{'command': 42}), isNull);
    });

    test('keeps unknown-but-well-formed names so the host can report them', () {
      final PluginCommand? command = PluginCommand.fromJson(<String, dynamic>{'command': 'teleport'});
      expect(command, isNotNull);
      expect(PluginCommand.knownCommands.contains(command!.name), isFalse);
    });

    test('ignores non-string payload fields', () {
      final PluginCommand command = PluginCommand.fromJson(<String, dynamic>{
        'command': 'toast',
        'text': 123,
        'url': <String>['not', 'a', 'url'],
      })!;
      expect(command.text, isNull);
      expect(command.url, isNull);
    });
  });

  group('PluginRenderFrame', () {
    test('still parses render lines and ignores command lines', () {
      expect(
        PluginRenderFrame.tryParseLine('{"type":"render","rev":2,"view":"list","items":[]}'),
        isNotNull,
      );
      expect(
        PluginRenderFrame.tryParseLine('{"type":"command","command":"copy","text":"x"}'),
        isNull,
      );
    });
  });
}
