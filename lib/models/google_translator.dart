// Converted from the uploaded TypeScript Google Translate files.
//
// pubspec.yaml dependency:
//   dependencies:
//     http: ^1.2.0

import 'dart:convert';

import 'package:http/http.dart' as http;

class GoogleTranslator {
  GoogleTranslator({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String _tkk = '0';

  final Map<String, String> _languages = <String, String>{
    'auto': 'Auto-Detect',
    'ab': 'Abkhaz',
    'ace': 'Acehnese',
    'ach': 'Acholi',
    'aa': 'Afar',
    'af': 'Afrikaans',
    'sq': 'Albanian',
    'alz': 'Alur',
    'am': 'Amharic',
    'ar': 'Arabic',
    'hy': 'Armenian',
    'as': 'Assamese',
    'av': 'Avar',
    'awa': 'Awadhi',
    'ay': 'Aymara',
    'az': 'Azerbaijani',
    'ban': 'Balinese',
    'bal': 'Baluchi',
    'bm': 'Bambara',
    'bci': 'Baoulé',
    'ba': 'Bashkir',
    'eu': 'Basque',
    'btx': 'Batak Karo',
    'bts': 'Batak Simalungun',
    'bbc': 'Batak Toba',
    'be': 'Belarusian',
    'bem': 'Bemba',
    'bn': 'Bengali',
    'bew': 'Betawi',
    'bho': 'Bhojpuri',
    'bik': 'Bikol',
    'bs': 'Bosnian',
    'br': 'Breton',
    'bg': 'Bulgarian',
    'bua': 'Buryat',
    'yue': 'Cantonese',
    'ca': 'Catalan',
    'ceb': 'Cebuano',
    'ch': 'Chamorro',
    'ce': 'Chechen',
    'ny': 'Chichewa',
    'zh-CN': 'Chinese (Simplified)',
    'zh-TW': 'Chinese (Traditional)',
    'chk': 'Chuukese',
    'cv': 'Chuvash',
    'co': 'Corsican',
    'crh': 'Crimean Tatar (Cyrillic)',
    'crh-Latn': 'Crimean Tatar (Latin)',
    'hr': 'Croatian',
    'cs': 'Czech',
    'da': 'Danish',
    'fa-AF': 'Dari',
    'dv': 'Dhivehi',
    'din': 'Dinka',
    'doi': 'Dogri',
    'dov': 'Dombe',
    'nl': 'Dutch',
    'dyu': 'Dyula',
    'dz': 'Dzongkha',
    'en': 'English',
    'eo': 'Esperanto',
    'et': 'Estonian',
    'ee': 'Ewe',
    'fo': 'Faroese',
    'fj': 'Fijian',
    'tl': 'Filipino',
    'fi': 'Finnish',
    'fon': 'Fon',
    'fr': 'French',
    'fr-CA': 'French (Canada)',
    'fy': 'Frisian',
    'fur': 'Friulian',
    'ff': 'Fulani',
    'gaa': 'Ga',
    'gl': 'Galician',
    'ka': 'Georgian',
    'de': 'German',
    'el': 'Greek',
    'gn': 'Guarani',
    'gu': 'Gujarati',
    'ht': 'Haitian Creole',
    'cnh': 'Hakha Chin',
    'ha': 'Hausa',
    'haw': 'Hawaiian',
    'iw': 'Hebrew',
    'hil': 'Hiligaynon',
    'hi': 'Hindi',
    'hmn': 'Hmong',
    'hu': 'Hungarian',
    'hrx': 'Hunsrik',
    'iba': 'Iban',
    'is': 'Icelandic',
    'ig': 'Igbo',
    'ilo': 'Ilocano',
    'id': 'Indonesian',
    'iu-Latn': 'Inuktut (Latin)',
    'iu': 'Inuktut (Syllabics)',
    'ga': 'Irish',
    'it': 'Italian',
    'jam': 'Jamaican Patois',
    'ja': 'Japanese',
    'jv': 'Javanese',
    'kac': 'Jingpo',
    'kl': 'Kalaallisut',
    'kn': 'Kannada',
    'kr': 'Kanuri',
    'pam': 'Kapampangan',
    'kk': 'Kazakh',
    'kha': 'Khasi',
    'km': 'Khmer',
    'cgg': 'Kiga',
    'kg': 'Kikongo',
    'rw': 'Kinyarwanda',
    'ktu': 'Kituba',
    'trp': 'Kokborok',
    'kv': 'Komi',
    'gom': 'Konkani',
    'ko': 'Korean',
    'kri': 'Krio',
    'ku': 'Kurdish (Kurmanji)',
    'ckb': 'Kurdish (Sorani)',
    'ky': 'Kyrgyz',
    'lo': 'Lao',
    'ltg': 'Latgalian',
    'la': 'Latin',
    'lv': 'Latvian',
    'lij': 'Ligurian',
    'li': 'Limburgish',
    'ln': 'Lingala',
    'lt': 'Lithuanian',
    'lmo': 'Lombard',
    'lg': 'Luganda',
    'luo': 'Luo',
    'lb': 'Luxembourgish',
    'mk': 'Macedonian',
    'mad': 'Madurese',
    'mai': 'Maithili',
    'mak': 'Makassar',
    'mg': 'Malagasy',
    'ms': 'Malay',
    'ms-Arab': 'Malay (Jawi)',
    'ml': 'Malayalam',
    'mt': 'Maltese',
    'mam': 'Mam',
    'gv': 'Manx',
    'mi': 'Maori',
    'mr': 'Marathi',
    'mh': 'Marshallese',
    'mwr': 'Marwadi',
    'mfe': 'Mauritian Creole',
    'chm': 'Meadow Mari',
    'mni-Mtei': 'Meiteilon (Manipuri)',
    'min': 'Minang',
    'lus': 'Mizo',
    'mn': 'Mongolian',
    'my': 'Myanmar (Burmese)',
    'bm-Nkoo': 'NKo',
    'nhe': 'Nahuatl (Eastern Huasteca)',
    'ndc-ZW': 'Ndau',
    'nr': 'Ndebele (South)',
    'new': 'Nepalbhasa (Newari)',
    'ne': 'Nepali',
    'no': 'Norwegian',
    'nus': 'Nuer',
    'oc': 'Occitan',
    'or': 'Odia (Oriya)',
    'om': 'Oromo',
    'os': 'Ossetian',
    'pag': 'Pangasinan',
    'pap': 'Papiamento',
    'ps': 'Pashto',
    'fa': 'Persian',
    'pl': 'Polish',
    'pt': 'Portuguese (Brazil)',
    'pt-PT': 'Portuguese (Portugal)',
    'pa': 'Punjabi (Gurmukhi)',
    'pa-Arab': 'Punjabi (Shahmukhi)',
    'qu': 'Quechua',
    'kek': 'Qʼeqchiʼ',
    'rom': 'Romani',
    'ro': 'Romanian',
    'rn': 'Rundi',
    'ru': 'Russian',
    'se': 'Sami (North)',
    'sm': 'Samoan',
    'sg': 'Sango',
    'sa': 'Sanskrit',
    'sat-Latn': 'Santali (Latin)',
    'sat': 'Santali (Ol Chiki)',
    'gd': 'Scots Gaelic',
    'nso': 'Sepedi',
    'sr': 'Serbian',
    'st': 'Sesotho',
    'crs': 'Seychellois Creole',
    'shn': 'Shan',
    'sn': 'Shona',
    'scn': 'Sicilian',
    'szl': 'Silesian',
    'sd': 'Sindhi',
    'si': 'Sinhala',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'so': 'Somali',
    'es': 'Spanish',
    'su': 'Sundanese',
    'sus': 'Susu',
    'sw': 'Swahili',
    'ss': 'Swati',
    'sv': 'Swedish',
    'ty': 'Tahitian',
    'tg': 'Tajik',
    'ber-Latn': 'Tamazight',
    'ber': 'Tamazight (Tifinagh)',
    'ta': 'Tamil',
    'tt': 'Tatar',
    'te': 'Telugu',
    'tet': 'Tetum',
    'th': 'Thai',
    'bo': 'Tibetan',
    'ti': 'Tigrinya',
    'tiv': 'Tiv',
    'tpi': 'Tok Pisin',
    'to': 'Tongan',
    'lua': 'Tshiluba',
    'ts': 'Tsonga',
    'tn': 'Tswana',
    'tcy': 'Tulu',
    'tum': 'Tumbuka',
    'tr': 'Turkish',
    'tk': 'Turkmen',
    'tyv': 'Tuvan',
    'ak': 'Twi',
    'udm': 'Udmurt',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'ug': 'Uyghur',
    'uz': 'Uzbek',
    've': 'Venda',
    'vec': 'Venetian',
    'vi': 'Vietnamese',
    'war': 'Waray',
    'cy': 'Welsh',
    'wo': 'Wolof',
    'xh': 'Xhosa',
    'sah': 'Yakut',
    'yi': 'Yiddish',
    'yo': 'Yoruba',
    'yua': 'Yucatec Maya',
    'zap': 'Zapotec',
    'zu': 'Zulu',
  };
  static Map<String, String> get languages => GoogleTranslator()._languages;

  Future<GoogleTranslateResponse> translate(
    String text, {
    String from = 'auto',
    String to = 'en',
    bool raw = false,
  }) async {
    from = _getIsoCode(from) ?? (throw ArgumentError("The language '$from' is not supported."));
    to = _getIsoCode(to) ?? (throw ArgumentError("The language '$to' is not supported."));

    final _Token token = await _tokenGenerator(text);
    final Uri baseUrl = Uri.parse('https://translate.google.com/translate_a/single');

    final Map<String, String> query = <String, String>{
      'client': 'gtx',
      'sl': from,
      'tl': to,
      'hl': to,
      'ie': 'UTF-8',
      'oe': 'UTF-8',
      'otf': '1',
      'ssel': '0',
      'tsel': '0',
      'kc': '7',
      'q': text,
      token.name: token.value,
    };

    final List<String> dtValues = <String>['at', 'bd', 'ex', 'ld', 'md', 'qca', 'rw', 'rm', 'ss', 't'];
    Uri buildUri(Map<String, String> params) {
      final String queryString = <String>[
        ...params.entries.map(
            (MapEntry<String, String> e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}'),
        ...dtValues.map((String dt) => 'dt=${Uri.encodeQueryComponent(dt)}'),
      ].join('&');
      return baseUrl.replace(query: queryString);
    }

    http.Response response;
    Uri uri = buildUri(query);
    if (uri.toString().length > 2048) {
      final Map<String, String> getParams = Map<String, String>.from(query)..remove('q');
      uri = buildUri(getParams);
      response = await _client.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'},
        body: 'q=${Uri.encodeQueryComponent(text)}',
      );
    } else {
      response = await _client.get(uri);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GoogleTranslateException(
          'Google Translate request failed with HTTP ${response.statusCode}.', response.body);
    }

    final dynamic body = jsonDecode(response.body);
    return _parseResponse(body, includeRaw: raw);
  }

  static bool isSupported(String? language) => _getIsoCode(language) != null;

  static String? getIsoCode(String? language) => _getIsoCode(language);

  static String? _getIsoCode(String? language) {
    if (language == null || language.isEmpty) return null;
    if (languages.containsKey(language)) return language;
    final String normalized = language.toLowerCase();
    if (languages.containsKey(normalized)) return normalized;
    for (final MapEntry<String, String> entry in languages.entries) {
      if (entry.value.toLowerCase() == normalized) return entry.key;
    }
    return null;
  }

  GoogleTranslateResponse _parseResponse(dynamic body, {required bool includeRaw}) {
    final StringBuffer translated = StringBuffer();
    final dynamic segments = body is List && body.isNotEmpty ? body[0] : null;
    if (segments is List) {
      for (final dynamic obj in segments) {
        if (obj is List && obj.isNotEmpty && obj[0] != null) translated.write(obj[0]);
      }
    }

    bool languageDidYouMean = false;
    String languageIso = '';
    if (body is List && body.length > 2 && body[2] != null) {
      languageIso = body[2].toString();
    }

    // body[8] is Google's "did you mean this language?" suggestion — only flag it,
    // don't replace the detected language with it
    if (body is List && body.length > 8 && body[8] is List && body[8].isNotEmpty && body[8][0] is List) {
      final String suggested = body[8][0][0]?.toString() ?? '';
      if (suggested.isNotEmpty && suggested != languageIso) {
        languageDidYouMean = true;
        // Do NOT override languageIso here
      }
    }

    String correctedText = '';
    bool autoCorrected = false;
    bool textDidYouMean = false;
    if (body is List && body.length > 7 && body[7] is List && body[7].isNotEmpty && body[7][0] != null) {
      correctedText = body[7][0].toString().replaceAll('<b><i>', '[').replaceAll('</i></b>', ']');
      if (body[7].length > 5 && body[7][5] == true) {
        autoCorrected = true;
      } else {
        textDidYouMean = true;
      }
    }

    return GoogleTranslateResponse(
      text: translated.toString(),
      from: GoogleTranslateFrom(
        language: GoogleTranslateLanguage(didYouMean: languageDidYouMean, iso: languageIso),
        text: GoogleTranslateSourceText(autoCorrected: autoCorrected, value: correctedText, didYouMean: textDidYouMean),
      ),
      raw: includeRaw ? body : null,
    );
  }

  Future<_Token> _tokenGenerator(String text) async {
    await _updateTkk();
    String tk = _zr(text);
    tk = tk.replaceFirst('&tk=', '');
    return _Token('tk', tk);
  }

  Future<void> _updateTkk() async {
    final int now = DateTime.now().millisecondsSinceEpoch ~/ 3600000;
    final int current = int.tryParse(_tkk.split('.').first) ?? 0;
    if (current == now) return;

    final http.Response response = await _client.get(Uri.parse('https://translate.google.com'));
    if (response.statusCode < 200 || response.statusCode >= 300) return;

    final RegExpMatch? match = RegExp(r"tkk:'(\d+\.\d+)'").firstMatch(response.body);
    if (match != null) _tkk = match.group(1)!;
  }

  String _zr(String input) {
    final List<String> d = _tkk.split('.');
    final int b = int.tryParse(d.isNotEmpty ? d[0] : '') ?? 0;

    final List<int> bytes = <int>[];
    final List<int> units = input.codeUnits;
    for (int g = 0; g < units.length; g++) {
      int l = units[g];
      if (l < 128) {
        bytes.add(l);
      } else {
        if (l < 2048) {
          bytes.add((l >> 6) | 192);
        } else {
          if ((l & 64512) == 55296 && g + 1 < units.length && (units[g + 1] & 64512) == 56320) {
            l = 65536 + ((l & 1023) << 10) + (units[++g] & 1023);
            bytes.add((l >> 18) | 240);
            bytes.add(((l >> 12) & 63) | 128);
          } else {
            bytes.add((l >> 12) | 224);
          }
          bytes.add(((l >> 6) & 63) | 128);
        }
        bytes.add((l & 63) | 128);
      }
    }

    int h = b;
    for (final int value in bytes) {
      h += value;
      h = _xr(h, '+-a^+6');
    }
    h = _xr(h, '+-3^+b+-f');
    h ^= int.tryParse(d.length > 1 ? d[1] : '') ?? 0;
    if (h < 0) h = (h & 2147483647) + 2147483648;
    h %= 1000000;
    return '&tk=${h.toString()}.${h ^ b}';
  }

  int _xr(int a, String b) {
    for (int c = 0; c < b.length - 2; c += 3) {
      final int d = b.codeUnitAt(c + 2);
      final int e = d >= 'a'.codeUnitAt(0) ? d - 87 : int.parse(String.fromCharCode(d));
      final int shifted = b[c + 1] == '+' ? (a & 0xffffffff) >>> e : (a << e);
      a = b[c] == '+' ? (a + shifted) & 0xffffffff : a ^ shifted;
    }
    return a;
  }

  void close() => _client.close();
}

class GoogleTranslateResponse {
  const GoogleTranslateResponse({required this.text, required this.from, this.raw});

  final String text;
  final GoogleTranslateFrom from;
  final dynamic raw;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'text': text,
        'from': from.toJson(),
        if (raw != null) 'raw': raw,
      };
}

class GoogleTranslateFrom {
  const GoogleTranslateFrom({required this.language, required this.text});

  final GoogleTranslateLanguage language;
  final GoogleTranslateSourceText text;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'language': language.toJson(),
        'text': text.toJson(),
      };
}

class GoogleTranslateLanguage {
  const GoogleTranslateLanguage({required this.didYouMean, required this.iso});

  final bool didYouMean;
  final String iso;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'didYouMean': didYouMean,
        'iso': iso,
      };
}

class GoogleTranslateSourceText {
  const GoogleTranslateSourceText({required this.autoCorrected, required this.value, required this.didYouMean});

  final bool autoCorrected;
  final String value;
  final bool didYouMean;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'autoCorrected': autoCorrected,
        'value': value,
        'didYouMean': didYouMean,
      };
}

class GoogleTranslateException implements Exception {
  const GoogleTranslateException(this.message, [this.body]);

  final String message;
  final String? body;

  @override
  String toString() => body == null ? message : '$message\n$body';
}

class _Token {
  const _Token(this.name, this.value);

  final String name;
  final String value;
}
