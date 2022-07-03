import 'dart:ffi';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';

enum KeySentMode {
  normal,
  down,
  up,
}

class WinKeys {
  /// Send Keys as Keyboard {#KEY} to send down {^KEY} to sendUp
  /// [keys] is a string that contains the keys to send.
  /// Format: {SPECIAL_KEY} to send special keys like CTRL WIN ALT etc.
  /// Format: add before special key # to send key down, and ^ to send key up like `{#CTRL}A{^CTRL}empty`
  /// Format: add {|} to clear down keys
  static bool send(String keys) {
    keys = keys.toUpperCase();
    //AB{#}{CTRL}{SHIFT}E{|}{#}{CTRL}EF{^}{CTRL}
    const Map<String, String> types = {'|': 'reset', '#': 'down', '^': 'up'};
    final map = <String>[];
    final keyIds = <int>[];
    for (var i = 0; i < keys.length; i++) {
      final c = keys[i];
      if (c == '{') {
        final end = keys.indexOf('}', i);
        if (end == -1) {
          return false;
        }
        var key = keys.substring(i + 1, end);
        if (key.contains("CTRL")) key = key.replaceAll("CTRL", "CONTROL");
        if (key.contains("ALT")) key = key.replaceAll("MENU", "MENU");
        if (key == " ") key = "space";
        i = end;
        if (['|', '#', '^'].contains(key[0]) && key.length > 1) {
          map.add("MODE_${types[key[0]]}");
          key = key.substring(1);
        }
        if (key == '|') {
          map.add("MODE_${types[key]}");
        } else {
          map.add("VK_$key");
        }
      } else {
        map.add("VK_$c");
      }
    }
    keyString.forEach((id, key) {
      if (key.length > 3) {}
      if (map.contains(key)) {
        //print(key);
        keyIds.add(id);
      }
    });
    return sendList(map);
  }

  /// Save as above but as a list of keys
  static bool sendList(List<String> keys) {
    if (keys.isEmpty) return false;
    var downKeys = <String>[];
    var mode = KeySentMode.normal;
    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      if (key == "MODE_down") {
        mode = KeySentMode.down;
      } else if (key == "MODE_up") {
        mode = KeySentMode.up;
      } else if (key == "MODE_reset") {
        for (var element in downKeys) {
          single(element, KeySentMode.up);
        }
        downKeys = [];
      } else {
        if (mode == KeySentMode.down) {
          downKeys.add(key);
          single(key, KeySentMode.down);
          mode = KeySentMode.normal;
        } else if (mode == KeySentMode.up) {
          downKeys.remove(key);
          single(key, KeySentMode.up);
        } else {
          single(key, KeySentMode.normal);
        }
      }
    }
    bool result = true;
    for (var element in downKeys) {
      final r = single(element, KeySentMode.up);
      if (r == false) result = false;
    }
    return result;
  }

  /// Send a single key
  /// [key] is the key to send.
  /// [mode] is the mode to send the key.
  /// [mode] can be [KeySentMode.normal], [KeySentMode.down] or [KeySentMode.up]
  static bool single(String key, KeySentMode mode) {
    int keyValue = keyMap[key] ?? 0;
    // MapEntry entry = keyString.entries.firstWhere((entry) => entry.value == key, orElse: () => const MapEntry<int, String>(0, ""));
    if (keyValue == 0) {
      print("no key $key");
      return false;
    }
    final input = calloc<INPUT>();
    input.ref.type = INPUT_KEYBOARD;
    if (mode == KeySentMode.up) {
      input.ref.ki.dwFlags = KEYEVENTF_KEYUP;
    } else {
      input.ref.ki.dwFlags = WM_KEYDOWN;
    }
    input.ref.ki.wVk = keyValue;
    SendInput(1, input, sizeOf<INPUT>());
    free(input);
    if (mode == KeySentMode.normal) {
      final input = calloc<INPUT>();
      input.ref.type = INPUT_KEYBOARD;
      input.ref.ki.dwFlags = KEYEVENTF_KEYUP;
      input.ref.ki.wVk = keyValue;
      SendInput(1, input, sizeOf<INPUT>());
    }
    return true;
  }
}

// #region (collapsed) keyString
const keyString = <int, String>{
  1: "VK_LBUTTON",
  2: "VK_RBUTTON",
  3: "VK_CANCEL",
  4: "VK_MBUTTON",
  5: "VK_XBUTTON1",
  6: "VK_XBUTTON2",
  8: "VK_BACK",
  9: "VK_TAB",
  10: "VK_TERMINATE1",
  11: "VK_TERMINATE2",
  12: "VK_CLEAR",
  13: "VK_RETURN",
  16: "VK_SHIFT",
  17: "VK_CONTROL",
  18: "VK_MENU",
  19: "VK_PAUSE",
  20: "VK_CAPITAL",
  21: "VK_KANA",
  23: "VK_JUNJA",
  24: "VK_FINAL",
  25: "VK_HANJA",
  27: "VK_ESCAPE",
  28: "VK_CONVERT",
  29: "VK_NONCONVERT",
  30: "VK_ACCEPT",
  31: "VK_MODECHANGE",
  32: "VK_SPACE",
  33: "VK_PRIOR",
  34: "VK_NEXT",
  35: "VK_END",
  36: "VK_HOME",
  37: "VK_LEFT",
  38: "VK_UP",
  39: "VK_RIGHT",
  40: "VK_DOWN",
  41: "VK_SELECT",
  42: "VK_PRINT",
  43: "VK_EXECUTE",
  44: "VK_SNAPSHOT",
  45: "VK_INSERT",
  46: "VK_DELETE",
  47: "VK_HELP",
  48: "VK_0",
  49: "VK_1",
  50: "VK_2",
  51: "VK_3",
  52: "VK_4",
  53: "VK_5",
  54: "VK_6",
  55: "VK_7",
  56: "VK_8",
  57: "VK_9",
  65: "VK_A",
  66: "VK_B",
  67: "VK_C",
  68: "VK_D",
  69: "VK_E",
  70: "VK_F",
  71: "VK_G",
  72: "VK_H",
  73: "VK_I",
  74: "VK_J",
  75: "VK_K",
  76: "VK_L",
  77: "VK_M",
  78: "VK_N",
  79: "VK_O",
  80: "VK_P",
  81: "VK_Q",
  82: "VK_R",
  83: "VK_S",
  84: "VK_T",
  85: "VK_U",
  86: "VK_V",
  87: "VK_W",
  88: "VK_X",
  89: "VK_Y",
  90: "VK_Z",
  91: "VK_LWIN",
  92: "VK_RWIN",
  93: "VK_APPS",
  95: "VK_SLEEP",
  96: "VK_NUMPAD0",
  97: "VK_NUMPAD1",
  98: "VK_NUMPAD2",
  99: "VK_NUMPAD3",
  100: "VK_NUMPAD4",
  101: "VK_NUMPAD5",
  102: "VK_NUMPAD6",
  103: "VK_NUMPAD7",
  104: "VK_NUMPAD8",
  105: "VK_NUMPAD9",
  106: "VK_MULTIPLY",
  107: "VK_ADD",
  108: "VK_SEPARATOR",
  109: "VK_SUBTRACT",
  110: "VK_DECIMAL",
  111: "VK_DIVIDE",
  112: "VK_F1",
  113: "VK_F2",
  114: "VK_F3",
  115: "VK_F4",
  116: "VK_F5",
  117: "VK_F6",
  118: "VK_F7",
  119: "VK_F8",
  120: "VK_F9",
  121: "VK_F10",
  122: "VK_F11",
  123: "VK_F12",
  124: "VK_F13",
  125: "VK_F14",
  126: "VK_F15",
  127: "VK_F16",
  128: "VK_F17",
  129: "VK_F18",
  130: "VK_F19",
  131: "VK_F20",
  132: "VK_F21",
  133: "VK_F22",
  134: "VK_F23",
  135: "VK_F24",
  144: "VK_NUMLOCK",
  145: "VK_SCROLL",
  160: "VK_LSHIFT",
  161: "VK_RSHIFT",
  162: "VK_LCONTROL",
  163: "VK_RCONTROL",
  164: "VK_LMENU",
  165: "VK_RMENU",
  166: "VK_BROWSER_BACK",
  167: "VK_BROWSER_FORWARD",
  168: "VK_BROWSER_REFRESH",
  169: "VK_BROWSER_STOP",
  170: "VK_BROWSER_SEARCH",
  171: "VK_BROWSER_FAVORITES",
  172: "VK_BROWSER_HOME",
  173: "VK_VOLUME_MUTE",
  174: "VK_VOLUME_DOWN",
  175: "VK_VOLUME_UP",
  176: "VK_MEDIA_NEXT_TRACK",
  177: "VK_MEDIA_PREV_TRACK",
  178: "VK_MEDIA_STOP",
  179: "VK_MEDIA_PLAY_PAUSE",
  180: "VK_LAUNCH_MAIL",
  181: "VK_LAUNCH_MEDIA_SELECT",
  182: "VK_LAUNCH_APP1",
  183: "VK_LAUNCH_APP2",
  186: "VK_;",
  187: "VK_+",
  188: "VK_,",
  189: "VK_-",
  190: "VK_.",
  191: "VK_/",
  192: "VK_`",
  219: "VK_[",
  220: "VK_\\",
  221: "VK_]",
  222: "VK_'",
  223: "VK_'",
  226: "VK_<",
  229: "VK_PROCESSKEY",
  231: "VK_PACKET",
  246: "VK_ATTN",
  247: "VK_CRSEL",
  248: "VK_EXSEL",
  249: "VK_EREOF",
  250: "VK_PLAY",
  251: "VK_ZOOM",
  252: "VK_NONAME",
  253: "VK_PA1",
  254: "VK_OEM_CLEAR",
};
const Map<String, int> keyMap = {
  "VK_LBUTTON": 1,
  "VK_RBUTTON": 2,
  "VK_CANCEL": 3,
  "VK_MBUTTON": 4,
  "VK_XBUTTON1": 5,
  "VK_XBUTTON2": 6,
  "VK_BACK": 8,
  "VK_TAB": 9,
  "VK_TERMINATE1": 10,
  "VK_TERMINATE2": 11,
  "VK_CLEAR": 12,
  "VK_RETURN": 13,
  "VK_SHIFT": 16,
  "VK_CONTROL": 17,
  "VK_CTRL": 17,
  "VK_MENU": 18,
  "VK_ALT": 18,
  "VK_PAUSE": 19,
  "VK_CAPITAL": 20,
  "VK_KANA": 21,
  "VK_JUNJA": 23,
  "VK_FINAL": 24,
  "VK_HANJA": 25,
  "VK_ESCAPE": 27,
  "VK_ESC": 27,
  "VK_CONVERT": 28,
  "VK_NONCONVERT": 29,
  "VK_ACCEPT": 30,
  "VK_MODECHANGE": 31,
  "VK_SPACE": 32,
  "VK_PRIOR": 33,
  "VK_NEXT": 34,
  "VK_END": 35,
  "VK_HOME": 36,
  "VK_LEFT": 37,
  "VK_UP": 38,
  "VK_RIGHT": 39,
  "VK_DOWN": 40,
  "VK_SELECT": 41,
  "VK_PRINT": 42,
  "VK_EXECUTE": 43,
  "VK_SNAPSHOT": 44,
  "VK_INSERT": 45,
  "VK_DELETE": 46,
  "VK_HELP": 47,
  "VK_0": 48,
  "VK_1": 49,
  "VK_2": 50,
  "VK_3": 51,
  "VK_4": 52,
  "VK_5": 53,
  "VK_6": 54,
  "VK_7": 55,
  "VK_8": 56,
  "VK_9": 57,
  "VK_A": 65,
  "VK_B": 66,
  "VK_C": 67,
  "VK_D": 68,
  "VK_E": 69,
  "VK_F": 70,
  "VK_G": 71,
  "VK_H": 72,
  "VK_I": 73,
  "VK_J": 74,
  "VK_K": 75,
  "VK_L": 76,
  "VK_M": 77,
  "VK_N": 78,
  "VK_O": 79,
  "VK_P": 80,
  "VK_Q": 81,
  "VK_R": 82,
  "VK_S": 83,
  "VK_T": 84,
  "VK_U": 85,
  "VK_V": 86,
  "VK_W": 87,
  "VK_X": 88,
  "VK_Y": 89,
  "VK_Z": 90,
  "VK_LWIN": 91,
  "VK_RWIN": 92,
  "VK_APPS": 93,
  "VK_SLEEP": 95,
  "VK_NUMPAD0": 96,
  "VK_NUMPAD1": 97,
  "VK_NUMPAD2": 98,
  "VK_NUMPAD3": 99,
  "VK_NUMPAD4": 100,
  "VK_NUMPAD5": 101,
  "VK_NUMPAD6": 102,
  "VK_NUMPAD7": 103,
  "VK_NUMPAD8": 104,
  "VK_NUMPAD9": 105,
  "VK_MULTIPLY": 106,
  "VK_ADD": 107,
  "VK_SEPARATOR": 108,
  "VK_SUBTRACT": 109,
  "VK_DECIMAL": 110,
  "VK_DIVIDE": 111,
  "VK_F1": 112,
  "VK_F2": 113,
  "VK_F3": 114,
  "VK_F4": 115,
  "VK_F5": 116,
  "VK_F6": 117,
  "VK_F7": 118,
  "VK_F8": 119,
  "VK_F9": 120,
  "VK_F10": 121,
  "VK_F11": 122,
  "VK_F12": 123,
  "VK_F13": 124,
  "VK_F14": 125,
  "VK_F15": 126,
  "VK_F16": 127,
  "VK_F17": 128,
  "VK_F18": 129,
  "VK_F19": 130,
  "VK_F20": 131,
  "VK_F21": 132,
  "VK_F22": 133,
  "VK_F23": 134,
  "VK_F24": 135,
  "VK_NUMLOCK": 144,
  "VK_SCROLL": 145,
  "VK_LSHIFT": 160,
  "VK_RSHIFT": 161,
  "VK_LCONTROL": 162,
  "VK_RCONTROL": 163,
  "VK_LCTRL": 162,
  "VK_RCTRL": 163,
  "VK_LMENU": 164,
  "VK_RMENU": 165,
  "VK_LALT": 164,
  "VK_RALT": 165,
  "VK_BROWSER_BACK": 166,
  "VK_BROWSER_FORWARD": 167,
  "VK_BROWSER_REFRESH": 168,
  "VK_BROWSER_STOP": 169,
  "VK_BROWSER_SEARCH": 170,
  "VK_BROWSER_FAVORITES": 171,
  "VK_BROWSER_HOME": 172,
  "VK_VOLUME_MUTE": 173,
  "VK_VOLUME_DOWN": 174,
  "VK_VOLUME_UP": 175,
  "VK_MEDIA_NEXT_TRACK": 176,
  "VK_MEDIA_PREV_TRACK": 177,
  "VK_MEDIA_STOP": 178,
  "VK_MEDIA_PLAY_PAUSE": 179,
  "VK_LAUNCH_MAIL": 180,
  "VK_LAUNCH_MEDIA_SELECT": 181,
  "VK_LAUNCH_APP1": 182,
  "VK_LAUNCH_APP2": 183,
  "VK_;": 186,
  "VK_+": 187,
  "VK_,": 188,
  "VK_-": 189,
  "VK_.": 190,
  "VK_/": 191,
  "VK_`": 192,
  "VK_[": 219,
  "VK_\\": 220,
  "VK_]": 221,
  "VK_'": 222,
  "VK_|": 223,
  "VK_<": 226,
  "VK_PROCESSKEY": 229,
  "VK_PACKET": 231,
  "VK_ATTN": 246,
  "VK_CRSEL": 247,
  "VK_EXSEL": 248,
  "VK_EREOF": 249,
  "VK_PLAY": 250,
  "VK_ZOOM": 251,
  "VK_NONAME": 252,
  "VK_PA1": 253,
  "VK_OEM_CLEAR": 254,
};
// #endregion