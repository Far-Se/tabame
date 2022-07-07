// ignore_for_file: non_constant_identifier_names

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
    const Map<String, String> types = {'|': 'reset', '#': 'down', '^': 'up'};
    final map = <String>[];
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
          if (["MENU", "CONTROL", "WIN", "SHIFT"].contains(key)) key = "L$key";
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
    final input = calloc<INPUT>();
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
      final input = calloc<INPUT>();
      input.ref.type = INPUT_KEYBOARD;
      input.ref.ki.dwFlags = KEYEVENTF_KEYUP;
      input.ref.ki.wVk = keyValue;
      SendInput(1, input, sizeOf<INPUT>());
    }
    return true;
  }

  static String vk(int vk) {
    for (var key in keyMap.keys) {
      if (keyMap[key] == vk) {
        return key;
      }
    }
    return "VK_";
  }
}

// #region (collapsed) Key Map
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

class VK {
  static String LBUTTON = "VK_LBUTTON";
  static String RBUTTON = "VK_RBUTTON";
  static String CANCEL = "VK_CANCEL";
  static String MBUTTON = "VK_MBUTTON";
  static String XBUTTON1 = "VK_XBUTTON1";
  static String XBUTTON2 = "VK_XBUTTON2";
  static String BACK = "VK_BACK";
  static String TAB = "VK_TAB";
  static String CLEAR = "VK_CLEAR";
  static String RETURN = "VK_RETURN";
  static String SHIFT = "VK_SHIFT";
  static String CONTROL = "VK_CONTROL";
  static String MENU = "VK_MENU";
  static String PAUSE = "VK_PAUSE";
  static String CAPITAL = "VK_CAPITAL";
  static String KANA = "VK_KANA";
  static String HANGEUL = "VK_HANGEUL";
  static String HANGUL = "VK_HANGUL";
  static String JUNJA = "VK_JUNJA";
  static String FINAL = "VK_FINAL";
  static String HANJA = "VK_HANJA";
  static String KANJI = "VK_KANJI";
  static String ESCAPE = "VK_ESCAPE";
  static String CONVERT = "VK_CONVERT";
  static String NONCONVERT = "VK_NONCONVERT";
  static String ACCEPT = "VK_ACCEPT";
  static String MODECHANGE = "VK_MODECHANGE";
  static String SPACE = "VK_SPACE";
  static String PRIOR = "VK_PRIOR";
  static String NEXT = "VK_NEXT";
  static String END = "VK_END";
  static String HOME = "VK_HOME";
  static String LEFT = "VK_LEFT";
  static String UP = "VK_UP";
  static String RIGHT = "VK_RIGHT";
  static String DOWN = "VK_DOWN";
  static String SELECT = "VK_SELECT";
  static String PRINT = "VK_PRINT";
  static String EXECUTE = "VK_EXECUTE";
  static String SNAPSHOT = "VK_SNAPSHOT";
  static String INSERT = "VK_INSERT";
  static String DELETE = "VK_DELETE";
  static String HELP = "VK_HELP";
  static String LWIN = "VK_LWIN";
  static String RWIN = "VK_RWIN";
  static String APPS = "VK_APPS";
  static String SLEEP = "VK_SLEEP";
  static String NUMPAD0 = "VK_NUMPAD0";
  static String NUMPAD1 = "VK_NUMPAD1";
  static String NUMPAD2 = "VK_NUMPAD2";
  static String NUMPAD3 = "VK_NUMPAD3";
  static String NUMPAD4 = "VK_NUMPAD4";
  static String NUMPAD5 = "VK_NUMPAD5";
  static String NUMPAD6 = "VK_NUMPAD6";
  static String NUMPAD7 = "VK_NUMPAD7";
  static String NUMPAD8 = "VK_NUMPAD8";
  static String NUMPAD9 = "VK_NUMPAD9";
  static String MULTIPLY = "VK_MULTIPLY";
  static String ADD = "VK_ADD";
  static String SEPARATOR = "VK_SEPARATOR";
  static String SUBTRACT = "VK_SUBTRACT";
  static String DECIMAL = "VK_DECIMAL";
  static String DIVIDE = "VK_DIVIDE";
  static String F1 = "VK_F1";
  static String F2 = "VK_F2";
  static String F3 = "VK_F3";
  static String F4 = "VK_F4";
  static String F5 = "VK_F5";
  static String F6 = "VK_F6";
  static String F7 = "VK_F7";
  static String F8 = "VK_F8";
  static String F9 = "VK_F9";
  static String F10 = "VK_F10";
  static String F11 = "VK_F11";
  static String F12 = "VK_F12";
  static String F13 = "VK_F13";
  static String F14 = "VK_F14";
  static String F15 = "VK_F15";
  static String F16 = "VK_F16";
  static String F17 = "VK_F17";
  static String F18 = "VK_F18";
  static String F19 = "VK_F19";
  static String F20 = "VK_F20";
  static String F21 = "VK_F21";
  static String F22 = "VK_F22";
  static String F23 = "VK_F23";
  static String F24 = "VK_F24";
  static String NUMLOCK = "VK_NUMLOCK";
  static String SCROLL = "VK_SCROLL";
  static String LSHIFT = "VK_LSHIFT";
  static String RSHIFT = "VK_RSHIFT";
  static String LCONTROL = "VK_LCONTROL";
  static String RCONTROL = "VK_RCONTROL";
  static String LMENU = "VK_LMENU";
  static String RMENU = "VK_RMENU";
  static String BROWSER_BACK = "VK_BROWSER_BACK";
  static String BROWSER_FORWARD = "VK_BROWSER_FORWARD";
  static String BROWSER_REFRESH = "VK_BROWSER_REFRESH";
  static String BROWSER_STOP = "VK_BROWSER_STOP";
  static String BROWSER_SEARCH = "VK_BROWSER_SEARCH";
  static String BROWSER_FAVORITES = "VK_BROWSER_FAVORITES";
  static String BROWSER_HOME = "VK_BROWSER_HOME";
  static String VOLUME_MUTE = "VK_VOLUME_MUTE";
  static String VOLUME_DOWN = "VK_VOLUME_DOWN";
  static String VOLUME_UP = "VK_VOLUME_UP";
  static String MEDIA_NEXT_TRACK = "VK_MEDIA_NEXT_TRACK";
  static String MEDIA_PREV_TRACK = "VK_MEDIA_PREV_TRACK";
  static String MEDIA_STOP = "VK_MEDIA_STOP";
  static String MEDIA_PLAY_PAUSE = "VK_MEDIA_PLAY_PAUSE";
  static String LAUNCH_MAIL = "VK_LAUNCH_MAIL";
  static String LAUNCH_MEDIA_SELECT = "VK_LAUNCH_MEDIA_SELECT";
  static String LAUNCH_APP1 = "VK_LAUNCH_APP1";
  static String LAUNCH_APP2 = "VK_LAUNCH_APP2";
  static String OEM_1 = "VK_OEM_1";
  static String OEM_PLUS = "VK_OEM_PLUS";
  static String OEM_COMMA = "VK_OEM_COMMA";
  static String OEM_MINUS = "VK_OEM_MINUS";
  static String OEM_PERIOD = "VK_OEM_PERIOD";
  static String OEM_2 = "VK_OEM_2";
  static String OEM_3 = "VK_OEM_3";
  static String OEM_4 = "VK_OEM_4";
  static String OEM_5 = "VK_OEM_5";
  static String OEM_6 = "VK_OEM_6";
  static String OEM_7 = "VK_OEM_7";
  static String OEM_8 = "VK_OEM_8";
  static String OEM_AX = "VK_OEM_AX";
  static String OEM_102 = "VK_OEM_102";
  static String ICO_HELP = "VK_ICO_HELP";
  static String ICO_00 = "VK_ICO_00";
  static String PROCESSKEY = "VK_PROCESSKEY";
  static String ICO_CLEAR = "VK_ICO_CLEAR";
  static String PACKET = "VK_PACKET";
}
// #endregion