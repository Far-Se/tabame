// ignore_for_file: non_constant_identifier_names, constant_identifier_names

import 'dart:ffi';
import 'package:win32/win32.dart';
import 'package:ffi/ffi.dart';

import 'win32/imports.dart';

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
    const Map<String, String> types = <String, String>{'|': 'reset', '#': 'down', '^': 'up'};
    final List<String> map = <String>[];
    for (int i = 0; i < keys.length; i++) {
      final String c = keys[i];
      if (c == '{') {
        final int end = keys.indexOf('}', i);
        if (end == -1) {
          return false;
        }
        String key = keys.substring(i + 1, end);
        if (key.contains("CTRL")) key = key.replaceAll("CTRL", "CONTROL");
        if (key.contains("ALT")) key = key.replaceAll("MENU", "MENU");

        if (key == " ") key = "space";
        i = end;
        if (<String>['|', '#', '^'].contains(key[0]) && key.length > 1) {
          map.add("MODE_${types[key[0]]}");
          key = key.substring(1);
        }
        if (key == '|') {
          map.add("MODE_${types[key]}");
        } else {
          if (<String>["MENU", "CONTROL", "WIN", "SHIFT"].contains(key)) key = "L$key";
          map.add("VK_$key");
        }
      } else {
        map.add("VK_$c");
      }
    }
    return sendList(map);
  }

  /// Save as above but as a list of keys
  static bool sendList(List<String> keys) {
    if (keys.isEmpty) return false;
    List<String> downKeys = <String>[];
    KeySentMode mode = KeySentMode.normal;
    for (int i = 0; i < keys.length; i++) {
      final String key = keys[i];
      if (key == "MODE_down") {
        mode = KeySentMode.down;
      } else if (key == "MODE_up") {
        mode = KeySentMode.up;
      } else if (key == "MODE_reset") {
        for (String element in downKeys) {
          single(element, KeySentMode.up);
        }
        downKeys = <String>[];
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
    for (String element in downKeys) {
      final bool r = single(element, KeySentMode.up);
      if (r == false) result = false;
    }
    return result;
  }

  /// Send a single key
  /// [key] is the key to send.
  /// [mode] is the mode to send the key.
  /// [mode] can be [KeySentMode.normal], [KeySentMode.down] or [KeySentMode.up]
  static bool singleEvent(String key, KeySentMode mode) {
    // print("$key ${mode.toString()}");
    int keyValue = keyMap[key] ?? 0;
    if (keyValue == 0) {
      print("no key $key");
      return false;
    }
    if (mode == KeySentMode.up) {
      keybd_event(keyValue, MapVirtualKey(keyValue, 0), KEYEVENTF_KEYUP, 0);
    } else {
      keybd_event(keyValue, MapVirtualKey(keyValue, 0), KEYEVENTF_EXTENDEDKEY, 0);
      if (mode == KeySentMode.normal) {
        keybd_event(keyValue, MapVirtualKey(keyValue, 0), KEYEVENTF_KEYUP, 0);
      }
    }
    return true;
  }

  /// Send a single key
  /// [key] is the key to send.
  /// [mode] is the mode to send the key.
  /// [mode] can be [KeySentMode.normal], [KeySentMode.down] or [KeySentMode.up]
  static bool single(String key, KeySentMode mode) {
    // print(key);
    int keyValue = keyMap[key] ?? 0;
    if (keyValue == 0) {
      print("no key $key");
      return false;
    }
    final Pointer<INPUT> input = calloc<INPUT>();
    input.ref.type = INPUT_KEYBOARD;
    if (mode == KeySentMode.up) {
      input.ref.ki.dwFlags = KEYEVENTF_KEYUP;
    } else {
      input.ref.ki.dwFlags = WM_KEYDOWN;
    }
    input.ref.ki.wScan = MapVirtualKey(keyValue, 0);
    // input.ref.ki.dwFlags = 0; // See docs for flags (mm keys may need Extended key flag)
    // input.ref.ki.time = 0;
    input.ref.ki.wVk = keyValue;
    SendInput(1, input, sizeOf<INPUT>());
    free(input);
    if (mode == KeySentMode.normal) {
      final Pointer<INPUT> input = calloc<INPUT>();
      input.ref.type = INPUT_KEYBOARD;
      input.ref.ki.dwFlags = KEYEVENTF_KEYUP;
      input.ref.ki.wVk = keyValue;
      SendInput(1, input, sizeOf<INPUT>());
    }
    return true;
  }

  static String vk(int vk) {
    for (String key in keyMap.keys) {
      if (keyMap[key] == vk) {
        return key;
      }
    }
    return "VK_";
  }
}

// #region (collapsed) Key Map
const Map<String, int> keyMap = <String, int>{
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

class VK {
  static const String LBUTTON = "VK_LBUTTON";
  static const String RBUTTON = "VK_RBUTTON";
  static const String CANCEL = "VK_CANCEL";
  static const String MBUTTON = "VK_MBUTTON";
  static const String XBUTTON1 = "VK_XBUTTON1";
  static const String XBUTTON2 = "VK_XBUTTON2";
  static const String BACK = "VK_BACK";
  static const String TAB = "VK_TAB";
  static const String CLEAR = "VK_CLEAR";
  static const String RETURN = "VK_RETURN";
  static const String SHIFT = "VK_SHIFT";
  static const String CONTROL = "VK_CONTROL";
  static const String MENU = "VK_MENU";
  static const String PAUSE = "VK_PAUSE";
  static const String CAPITAL = "VK_CAPITAL";
  static const String KANA = "VK_KANA";
  static const String HANGEUL = "VK_HANGEUL";
  static const String HANGUL = "VK_HANGUL";
  static const String JUNJA = "VK_JUNJA";
  static const String FINAL = "VK_FINAL";
  static const String HANJA = "VK_HANJA";
  static const String KANJI = "VK_KANJI";
  static const String ESCAPE = "VK_ESCAPE";
  static const String CONVERT = "VK_CONVERT";
  static const String NONCONVERT = "VK_NONCONVERT";
  static const String ACCEPT = "VK_ACCEPT";
  static const String MODECHANGE = "VK_MODECHANGE";
  static const String SPACE = "VK_SPACE";
  static const String PRIOR = "VK_PRIOR";
  static const String NEXT = "VK_NEXT";
  static const String END = "VK_END";
  static const String HOME = "VK_HOME";
  static const String LEFT = "VK_LEFT";
  static const String UP = "VK_UP";
  static const String RIGHT = "VK_RIGHT";
  static const String DOWN = "VK_DOWN";
  static const String SELECT = "VK_SELECT";
  static const String PRINT = "VK_PRINT";
  static const String EXECUTE = "VK_EXECUTE";
  static const String SNAPSHOT = "VK_SNAPSHOT";
  static const String INSERT = "VK_INSERT";
  static const String DELETE = "VK_DELETE";
  static const String HELP = "VK_HELP";
  static const String LWIN = "VK_LWIN";
  static const String RWIN = "VK_RWIN";
  static const String APPS = "VK_APPS";
  static const String SLEEP = "VK_SLEEP";
  static const String NUMPAD0 = "VK_NUMPAD0";
  static const String NUMPAD1 = "VK_NUMPAD1";
  static const String NUMPAD2 = "VK_NUMPAD2";
  static const String NUMPAD3 = "VK_NUMPAD3";
  static const String NUMPAD4 = "VK_NUMPAD4";
  static const String NUMPAD5 = "VK_NUMPAD5";
  static const String NUMPAD6 = "VK_NUMPAD6";
  static const String NUMPAD7 = "VK_NUMPAD7";
  static const String NUMPAD8 = "VK_NUMPAD8";
  static const String NUMPAD9 = "VK_NUMPAD9";
  static const String MULTIPLY = "VK_MULTIPLY";
  static const String ADD = "VK_ADD";
  static const String SEPARATOR = "VK_SEPARATOR";
  static const String SUBTRACT = "VK_SUBTRACT";
  static const String DECIMAL = "VK_DECIMAL";
  static const String DIVIDE = "VK_DIVIDE";
  static const String F1 = "VK_F1";
  static const String F2 = "VK_F2";
  static const String F3 = "VK_F3";
  static const String F4 = "VK_F4";
  static const String F5 = "VK_F5";
  static const String F6 = "VK_F6";
  static const String F7 = "VK_F7";
  static const String F8 = "VK_F8";
  static const String F9 = "VK_F9";
  static const String F10 = "VK_F10";
  static const String F11 = "VK_F11";
  static const String F12 = "VK_F12";
  static const String F13 = "VK_F13";
  static const String F14 = "VK_F14";
  static const String F15 = "VK_F15";
  static const String F16 = "VK_F16";
  static const String F17 = "VK_F17";
  static const String F18 = "VK_F18";
  static const String F19 = "VK_F19";
  static const String F20 = "VK_F20";
  static const String F21 = "VK_F21";
  static const String F22 = "VK_F22";
  static const String F23 = "VK_F23";
  static const String F24 = "VK_F24";
  static const String NUMLOCK = "VK_NUMLOCK";
  static const String SCROLL = "VK_SCROLL";
  static const String LSHIFT = "VK_LSHIFT";
  static const String RSHIFT = "VK_RSHIFT";
  static const String LCONTROL = "VK_LCONTROL";
  static const String RCONTROL = "VK_RCONTROL";
  static const String LMENU = "VK_LMENU";
  static const String RMENU = "VK_RMENU";
  static const String BROWSER_BACK = "VK_BROWSER_BACK";
  static const String BROWSER_FORWARD = "VK_BROWSER_FORWARD";
  static const String BROWSER_REFRESH = "VK_BROWSER_REFRESH";
  static const String BROWSER_STOP = "VK_BROWSER_STOP";
  static const String BROWSER_SEARCH = "VK_BROWSER_SEARCH";
  static const String BROWSER_FAVORITES = "VK_BROWSER_FAVORITES";
  static const String BROWSER_HOME = "VK_BROWSER_HOME";
  static const String VOLUME_MUTE = "VK_VOLUME_MUTE";
  static const String VOLUME_DOWN = "VK_VOLUME_DOWN";
  static const String VOLUME_UP = "VK_VOLUME_UP";
  static const String MEDIA_NEXT_TRACK = "VK_MEDIA_NEXT_TRACK";
  static const String MEDIA_PREV_TRACK = "VK_MEDIA_PREV_TRACK";
  static const String MEDIA_STOP = "VK_MEDIA_STOP";
  static const String MEDIA_PLAY_PAUSE = "VK_MEDIA_PLAY_PAUSE";
  static const String LAUNCH_MAIL = "VK_LAUNCH_MAIL";
  static const String LAUNCH_MEDIA_SELECT = "VK_LAUNCH_MEDIA_SELECT";
  static const String LAUNCH_APP1 = "VK_LAUNCH_APP1";
  static const String LAUNCH_APP2 = "VK_LAUNCH_APP2";
  static const String OEM_1 = "VK_OEM_1";
  static const String OEM_PLUS = "VK_OEM_PLUS";
  static const String OEM_COMMA = "VK_OEM_COMMA";
  static const String OEM_MINUS = "VK_OEM_MINUS";
  static const String OEM_PERIOD = "VK_OEM_PERIOD";
  static const String OEM_2 = "VK_OEM_2";
  static const String OEM_3 = "VK_OEM_3";
  static const String OEM_4 = "VK_OEM_4";
  static const String OEM_5 = "VK_OEM_5";
  static const String OEM_6 = "VK_OEM_6";
  static const String OEM_7 = "VK_OEM_7";
  static const String OEM_8 = "VK_OEM_8";
  static const String OEM_AX = "VK_OEM_AX";
  static const String OEM_102 = "VK_OEM_102";
  static const String ICO_HELP = "VK_ICO_HELP";
  static const String ICO_00 = "VK_ICO_00";
  static const String PROCESSKEY = "VK_PROCESSKEY";
  static const String ICO_CLEAR = "VK_ICO_CLEAR";
  static const String PACKET = "VK_PACKET";
}
// #endregion