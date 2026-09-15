#ifndef TABAMEWIN32_TEXT_SNIPPETS
#define TABAMEWIN32_TEXT_SNIPPETS

#include <algorithm>
#include <cwctype>
#include <deque>
#include <functional>
#include <string>
#include <vector>
#include <windows.h>
#include <ole2.h>

// All state, hooks, timers, and method calls run on the platform thread.
// Hooks only match keywords. Dart renders templates outside the hook; a request
// is committed only while its input generation and target are still current.
struct TextSnippet {
  std::string id;
  std::wstring trigger;
  bool caseSensitive = true;
  bool wordBoundary = true;
  std::string appMode = "any";
  std::vector<std::wstring> apps;
  std::wstring windowTitle;
};

struct TextSnippetPreferences {
  bool autoExpand = false;
  std::string mode = "immediate";
  int pasteDelayMs = 100;
  bool restoreClipboard = true;
  bool undoOnEscape = true;
  bool completionSound = false;
  std::vector<std::wstring> excludedApps;
};

namespace SnippetInput {
static constexpr size_t kBufferMax = 256;
static std::deque<wchar_t> buffer;
static std::vector<TextSnippet> snippets;
static TextSnippetPreferences preferences;
static HWND bufferWindow = nullptr;
static HWND bufferFocus = nullptr;
static uint64_t generation = 0;
static int64_t nextRequest = 0;
static std::function<void(const std::string &, int64_t)> requestExpansion;

struct Pending {
  int64_t id = 0;
  uint64_t generation = 0;
  HWND window = nullptr;
  HWND focus = nullptr;
  ULONGLONG time = 0;
  std::wstring keyword;
  std::wstring suffix;
};
static Pending pending;

struct ClipboardItem { UINT format; HANDLE data; };
static constexpr SIZE_T kClipboardBackupMaxBytes = 32 * 1024 * 1024;
static std::vector<ClipboardItem> savedClipboard;
static DWORD pasteSequence = 0;
static HWND clipboardOwner = nullptr;
static UINT_PTR restoreTimer = 0;
static int restoreAttempts = 0;
static DWORD temporaryClipboardSequence = 0;
static DWORD restoredClipboardSequence = 0;
static UINT_PTR cursorTimer = 0;
static HWND pasteWindow = nullptr;
static HWND pasteFocus = nullptr;
static uint64_t pasteGeneration = 0;
static size_t caretLeft = 0;
static size_t undoCharacters = 0;
static std::wstring undoKeyword;

static HWND FocusedControl(HWND window) {
  GUITHREADINFO info = {};
  info.cbSize = sizeof(info);
  return GetGUIThreadInfo(GetWindowThreadProcessId(window, nullptr), &info) ? info.hwndFocus : nullptr;
}

static std::wstring Lower(std::wstring value) {
  if (!value.empty()) CharLowerBuffW(value.data(), static_cast<DWORD>(value.size()));
  return value;
}

static std::wstring Executable(HWND window) {
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  if (pid == GetCurrentProcessId()) return L"tabame.exe";
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return L"";
  wchar_t path[32768] = {};
  DWORD size = ARRAYSIZE(path);
  const bool ok = QueryFullProcessImageNameW(process, 0, path, &size) != FALSE;
  CloseHandle(process);
  if (!ok) return L"";
  std::wstring name(path, size);
  return Lower(name.substr(name.find_last_of(L"\\/") + 1));
}

static bool AppListed(const std::vector<std::wstring> &apps, const std::wstring &exe) {
  return std::any_of(apps.begin(), apps.end(), [&](const std::wstring &app) { return Lower(app) == exe; });
}

static bool TargetAllowed(HWND window) {
  if (!window || !IsWindow(window)) return false;
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  if (pid == GetCurrentProcessId()) return false;
  const HWND focus = FocusedControl(window);
  wchar_t name[64] = {};
  GetClassNameW(focus, name, ARRAYSIZE(name));
  const std::wstring control = Lower(name);
  if ((control == L"edit" || control.find(L"richedit") == 0) &&
      (GetWindowLongPtrW(focus, GWL_STYLE) & ES_PASSWORD)) return false;
  return !AppListed(preferences.excludedApps, Executable(window));
}

static bool RuleAllowed(const TextSnippet &snippet, HWND window, const std::wstring &exe) {
  const bool listed = AppListed(snippet.apps, exe);
  if (snippet.appMode == "only" && !listed) return false;
  if (snippet.appMode == "except" && listed) return false;
  if (!snippet.windowTitle.empty()) {
    wchar_t title[2048] = {};
    GetWindowTextW(window, title, ARRAYSIZE(title));
    if (Lower(title).find(Lower(snippet.windowTitle)) == std::wstring::npos) return false;
  }
  return true;
}

static void Key(std::vector<INPUT> &inputs, WORD vk, bool up = false) {
  INPUT input = {};
  input.type = INPUT_KEYBOARD;
  input.ki.wVk = vk;
  input.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
  inputs.push_back(input);
}

static void Press(std::vector<INPUT> &inputs, WORD vk, size_t count = 1) {
  for (size_t i = 0; i < count; i++) { Key(inputs, vk); Key(inputs, vk, true); }
}

static void ReleaseModifiers(std::vector<INPUT> &inputs) {
  static const WORD modifiers[] = {VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LSHIFT, VK_RSHIFT, VK_LWIN, VK_RWIN};
  for (WORD vk : modifiers) {
    if (GetAsyncKeyState(vk) & 0x8000) Key(inputs, vk, true);
  }
}

static bool Send(std::vector<INPUT> &inputs) {
  return inputs.empty() || SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT)) == inputs.size();
}

static HANDLE DuplicateClipboardData(UINT format, HANDLE original, SIZE_T &remainingBytes) {
  if (!original) return nullptr;
  // Display formats use the same handle types as their non-display variants.
  // OleDuplicateData only recognizes the latter when copying GDI objects.
  UINT copyFormat = format;
  if (format == CF_DSPBITMAP) copyFormat = CF_BITMAP;
  else if (format == CF_DSPMETAFILEPICT) copyFormat = CF_METAFILEPICT;
  else if (format == CF_DSPENHMETAFILE) copyFormat = CF_ENHMETAFILE;

  SIZE_T bytes = 0;
  switch (copyFormat) {
  case CF_BITMAP: {
    // GlobalSize on an HBITMAP can terminate the process with heap corruption.
    // Measure the bitmap through GDI, without treating its handle as HGLOBAL.
    BITMAP bitmap = {};
    if (GetObjectW(original, sizeof(bitmap), &bitmap) != sizeof(bitmap) ||
        bitmap.bmWidthBytes <= 0 || bitmap.bmHeight <= 0 || bitmap.bmPlanes == 0) return nullptr;
    const uint64_t planeBytes = static_cast<uint64_t>(bitmap.bmWidthBytes) * bitmap.bmHeight;
    if (planeBytes > remainingBytes / bitmap.bmPlanes) return nullptr;
    bytes = static_cast<SIZE_T>(planeBytes * bitmap.bmPlanes);
    break;
  }
  case CF_PALETTE: {
    const UINT entries = GetPaletteEntries(static_cast<HPALETTE>(original), 0, 0, nullptr);
    if (!entries) return nullptr;
    bytes = sizeof(LOGPALETTE) + static_cast<SIZE_T>(entries) * sizeof(PALETTEENTRY);
    break;
  }
  case CF_ENHMETAFILE:
    bytes = GetEnhMetaFileBits(static_cast<HENHMETAFILE>(original), 0, nullptr);
    break;
  case CF_METAFILEPICT: {
    // This format has an HGLOBAL wrapper containing a separately owned HMETAFILE.
    const SIZE_T wrapperBytes = GlobalSize(original);
    if (wrapperBytes < sizeof(METAFILEPICT) || wrapperBytes > remainingBytes) return nullptr;
    const auto pict = static_cast<const METAFILEPICT *>(GlobalLock(original));
    if (!pict) return nullptr;
    const UINT metafileBytes = GetMetaFileBitsEx(pict->hMF, 0, nullptr);
    GlobalUnlock(original);
    if (!metafileBytes) return nullptr;
    bytes = wrapperBytes + metafileBytes;
    break;
  }
  case CF_TEXT: case CF_OEMTEXT: case CF_UNICODETEXT: case CF_DSPTEXT:
  case CF_DIB: case CF_DIBV5: case CF_DIF: case CF_SYLK: case CF_TIFF:
  case CF_PENDATA: case CF_RIFF: case CF_WAVE: case CF_HDROP: case CF_LOCALE:
    bytes = GlobalSize(original);
    break;
  default:
    // Registered formats (HTML, RTF, PNG, etc.) contain global memory. Private
    // and owner-display formats have owner-specific lifetimes; leave those
    // clipboards intact rather than attempting to clone unknown handles.
    if (format < 0xC000 || format > 0xFFFF) return nullptr;
    bytes = GlobalSize(original);
    break;
  }
  if (!bytes || bytes > remainingBytes) return nullptr;

  // OleDuplicateData does not document special handling for enhanced metafiles.
  HANDLE copy = copyFormat == CF_ENHMETAFILE
      ? CopyEnhMetaFileW(static_cast<HENHMETAFILE>(original), nullptr)
      : OleDuplicateData(original, static_cast<CLIPFORMAT>(copyFormat), GMEM_MOVEABLE);
  if (copy) remainingBytes -= bytes;
  return copy;
}

static void FreeClipboardItem(ClipboardItem &item) {
  if (!item.data) return;
  switch (item.format) {
  case CF_BITMAP: case CF_DSPBITMAP: case CF_PALETTE: DeleteObject(item.data); break;
  case CF_ENHMETAFILE: case CF_DSPENHMETAFILE: DeleteEnhMetaFile(static_cast<HENHMETAFILE>(item.data)); break;
  case CF_METAFILEPICT: case CF_DSPMETAFILEPICT: {
    auto pict = static_cast<METAFILEPICT *>(GlobalLock(item.data));
    if (pict) { DeleteMetaFile(pict->hMF); GlobalUnlock(item.data); }
    GlobalFree(item.data);
    break;
  }
  default: GlobalFree(item.data); break;
  }
  item.data = nullptr;
}

static void DiscardSavedClipboard() {
  for (auto &item : savedClipboard) FreeClipboardItem(item);
  savedClipboard.clear();
}

static void CALLBACK RestoreClipboard(HWND, UINT, UINT_PTR timer, DWORD) {
  if (timer) KillTimer(nullptr, timer);
  restoreTimer = 0;
  if (pasteSequence && GetClipboardSequenceNumber() == pasteSequence) {
    if (!OpenClipboard(clipboardOwner)) {
      if (++restoreAttempts <= 10) restoreTimer = SetTimer(nullptr, 0, 100, RestoreClipboard);
      else { pasteSequence = 0; DiscardSavedClipboard(); }
      return;
    }
    if (EmptyClipboard()) {
      for (auto &item : savedClipboard) {
        if (SetClipboardData(item.format, item.data)) item.data = nullptr;
      }
    }
    CloseClipboard();
    restoredClipboardSequence = GetClipboardSequenceNumber();
  }
  pasteSequence = 0;
  DiscardSavedClipboard();
}

static void CancelCaret() {
  if (cursorTimer) KillTimer(nullptr, cursorTimer);
  cursorTimer = 0;
  undoCharacters = 0;
  undoKeyword.clear();
}

static void Invalidate(bool clearBuffer) {
  ++generation;
  pending = Pending{};
  CancelCaret();
  if (clearBuffer) buffer.clear();
}

static void CALLBACK PlaceCursor(HWND, UINT, UINT_PTR timer, DWORD) {
  KillTimer(nullptr, timer);
  cursorTimer = 0;
  if (pasteGeneration != generation || GetForegroundWindow() != pasteWindow || FocusedControl(pasteWindow) != pasteFocus) {
    CancelCaret();
    return;
  }
  std::vector<INPUT> inputs;
  Press(inputs, VK_LEFT, caretLeft);
  if (!Send(inputs)) CancelCaret();
}

static size_t CharacterCount(const std::wstring &text) {
  size_t count = 0;
  for (wchar_t ch : text) if (ch < 0xDC00 || ch > 0xDFFF) ++count;
  return count;
}

static HGLOBAL HtmlClipboardData(const std::string &fragment) {
  std::string header = "Version:0.9\r\nStartHTML:0000000000\r\nEndHTML:0000000000\r\nStartFragment:0000000000\r\nEndFragment:0000000000\r\n";
  const std::string prefix = "<html><body><!--StartFragment-->";
  const std::string suffix = "<!--EndFragment--></body></html>";
  const size_t start = header.size();
  auto offset = [&](const std::string &label, size_t value) {
    const std::string digits = std::to_string(value);
    header.replace(header.find(label) + label.size(), 10, std::string(10 - digits.size(), '0') + digits);
  };
  offset("StartHTML:", start);
  offset("EndHTML:", start + prefix.size() + fragment.size() + suffix.size());
  offset("StartFragment:", start + prefix.size());
  offset("EndFragment:", start + prefix.size() + fragment.size());
  const std::string html = header + prefix + fragment + suffix;
  HGLOBAL data = GlobalAlloc(GMEM_MOVEABLE, html.size() + 1);
  if (!data) return nullptr;
  void *memory = GlobalLock(data);
  if (!memory) { GlobalFree(data); return nullptr; }
  memcpy(memory, html.c_str(), html.size() + 1);
  GlobalUnlock(data);
  return data;
}

static bool WriteClipboard(const std::wstring &text, const std::string &html, bool restore) {
  if (text.size() > 262144 || html.size() > 1048576) return false;
  if (restoreTimer) RestoreClipboard(nullptr, 0, restoreTimer, 0);
  if (restoreTimer) return false;
  CancelCaret();
  std::wstring windowsText;
  for (wchar_t ch : text) { if (ch == L'\n') windowsText += L'\r'; windowsText += ch; }
  const SIZE_T bytes = (windowsText.size() + 1) * sizeof(wchar_t);
  HGLOBAL data = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!data) return false;
  void *memory = GlobalLock(data);
  if (!memory) { GlobalFree(data); return false; }
  memcpy(memory, windowsText.c_str(), bytes);
  GlobalUnlock(data);
  HGLOBAL htmlData = html.empty() ? nullptr : HtmlClipboardData(html);
  if ((!html.empty() && !htmlData) || !OpenClipboard(clipboardOwner)) {
    GlobalFree(data); if (htmlData) GlobalFree(htmlData); return false;
  }
  bool captured = true;
  SIZE_T remainingBytes = kClipboardBackupMaxBytes;
  if (restore) {
    for (UINT format = EnumClipboardFormats(0); format; format = EnumClipboardFormats(format)) {
      if (savedClipboard.size() >= 64) { captured = false; break; }
      HANDLE copy = DuplicateClipboardData(format, GetClipboardData(format), remainingBytes);
      if (!copy) { captured = false; break; }
      savedClipboard.push_back({format, copy});
    }
  }
  if (!captured || !EmptyClipboard()) {
    CloseClipboard(); GlobalFree(data); if (htmlData) GlobalFree(htmlData); DiscardSavedClipboard(); return false;
  }
  const bool textCopied = SetClipboardData(CF_UNICODETEXT, data) != nullptr;
  const bool htmlCopied = !htmlData || SetClipboardData(RegisterClipboardFormatW(L"HTML Format"), htmlData) != nullptr;
  pasteSequence = GetClipboardSequenceNumber();
  CloseClipboard();
  if (!textCopied || !htmlCopied) {
    if (!textCopied) GlobalFree(data);
    if (!htmlCopied) GlobalFree(htmlData);
    if (restore) RestoreClipboard(nullptr, 0, 0, 0);
    else pasteSequence = 0;
    return false;
  }
  if (!restore) pasteSequence = 0;
  return true;
}

static bool Paste(HWND target, const std::wstring &text, size_t remove,
                  size_t left, size_t characters, const std::wstring &original, const std::string &html) {
  if (GetForegroundWindow() != target || !TargetAllowed(target) || left > characters) return false;
  const HWND expectedFocus = FocusedControl(target);
  const uint64_t expectedGeneration = generation;
  const ULONGLONG preparationStart = GetTickCount64();
  if (!WriteClipboard(text, html, preferences.restoreClipboard)) return false;
  temporaryClipboardSequence = GetClipboardSequenceNumber();
  // Rendering delayed clipboard formats can pump messages or stall. Recheck
  // the destination after preparing the clipboard and before deleting text.
  if (GetForegroundWindow() != target || FocusedControl(target) != expectedFocus ||
      generation != expectedGeneration || GetTickCount64() - preparationStart > 1500) {
    if (preferences.restoreClipboard) RestoreClipboard(nullptr, 0, 0, 0);
    return false;
  }
  std::vector<INPUT> inputs;
  ReleaseModifiers(inputs);
  Press(inputs, VK_BACK, remove);
  if (!text.empty()) {
    Key(inputs, VK_CONTROL); Press(inputs, 'V'); Key(inputs, VK_CONTROL, true);
  }
  const bool sent = Send(inputs);
  buffer.clear();
  ++generation;
  pasteGeneration = generation;
  pasteWindow = target;
  pasteFocus = FocusedControl(target);
  caretLeft = left;
  restoreAttempts = 0;
  if (preferences.restoreClipboard) restoreTimer = SetTimer(nullptr, 0, preferences.pasteDelayMs + 250, RestoreClipboard);
  else { pasteSequence = 0; DiscardSavedClipboard(); }
  if (!sent) return false;
  if (preferences.completionSound) MessageBeep(MB_OK);
  if (preferences.undoOnEscape && html.empty() && characters > 0 && characters <= 512 &&
      text.find_first_of(L"\n\r\t") == std::wstring::npos && !original.empty()) {
    undoCharacters = characters;
    undoKeyword = original;
  }
  if (left) cursorTimer = SetTimer(nullptr, 0, preferences.pasteDelayMs, PlaceCursor);
  return true;
}

static bool Undo() {
  if (!undoCharacters || cursorTimer || pasteGeneration != generation ||
      GetForegroundWindow() != pasteWindow || FocusedControl(pasteWindow) != pasteFocus) return false;
  std::vector<INPUT> inputs;
  ReleaseModifiers(inputs);
  Press(inputs, VK_RIGHT, caretLeft);
  Press(inputs, VK_BACK, undoCharacters);
  for (wchar_t ch : undoKeyword) {
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = ch;
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT up = down;
    up.ki.dwFlags |= KEYEVENTF_KEYUP;
    inputs.push_back(down); inputs.push_back(up);
  }
  const bool sent = Send(inputs);
  Invalidate(true);
  return sent;
}

static bool WordCharacter(wchar_t ch) {
  WORD type = 0;
  GetStringTypeW(CT_CTYPE1, &ch, 1, &type);
  return ch == L'_' || (ch >= 0xD800 && ch <= 0xDFFF) || (type & (C1_ALPHA | C1_DIGIT)) != 0;
}

static bool Request(const std::wstring &candidate, const std::wstring &suffix) {
  const HWND target = GetForegroundWindow();
  if (target != bufferWindow || FocusedControl(target) != bufferFocus || !requestExpansion) return false;
  std::wstring exe;
  bool checkedTarget = false;
  const TextSnippet *best = nullptr;
  for (const TextSnippet &snippet : snippets) {
    if (snippet.trigger.empty() || snippet.trigger.size() > candidate.size()) continue;
    const size_t start = candidate.size() - snippet.trigger.size();
    const std::wstring tail = candidate.substr(start);
    if (snippet.caseSensitive ? tail != snippet.trigger :
        CompareStringOrdinal(tail.c_str(), static_cast<int>(tail.size()), snippet.trigger.c_str(),
                             static_cast<int>(snippet.trigger.size()), TRUE) != CSTR_EQUAL) continue;
    if (snippet.wordBoundary && start > 0 && WordCharacter(candidate[start - 1])) continue;
    if (!checkedTarget) {
      if (!TargetAllowed(target)) return false;
      exe = Executable(target);
      checkedTarget = true;
    }
    if (!RuleAllowed(snippet, target, exe)) continue;
    if (!best || snippet.trigger.size() > best->trigger.size()) best = &snippet;
  }
  if (!best) return false;
  pending = {++nextRequest, generation, target, FocusedControl(target), GetTickCount64(),
             candidate.substr(candidate.size() - best->trigger.size()), suffix};
  requestExpansion(best->id, pending.id);
  return true;
}
} // namespace SnippetInput

inline void SetTextSnippets(std::vector<TextSnippet> snippets, TextSnippetPreferences preferences,
                           std::function<void(const std::string &, int64_t)> request) {
  SnippetInput::Invalidate(true);
  SnippetInput::snippets = std::move(snippets);
  SnippetInput::preferences = std::move(preferences);
  SnippetInput::requestExpansion = std::move(request);
}

inline void CancelTextSnippet(int64_t request) {
  if (SnippetInput::pending.id == request) SnippetInput::pending = SnippetInput::Pending{};
}

inline bool CompleteTextSnippet(int64_t request, const std::wstring &text, int left, int characters, std::string html) {
  using namespace SnippetInput;
  if (!request || request != pending.id || pending.generation != generation ||
      GetForegroundWindow() != pending.window || FocusedControl(pending.window) != pending.focus ||
      GetTickCount64() - pending.time > 5000 || left < -1 || characters < 0) return false;
  const Pending current = pending;
  pending = Pending{};
  const bool keep = preferences.mode == "delimiterKeep";
  const std::wstring suffix = keep ? current.suffix : L"";
  if (!html.empty() && !suffix.empty()) {
    for (wchar_t ch : suffix) {
      if (ch == L'&') html += "&amp;";
      else if (ch == L'<') html += "&lt;";
      else if (ch == L'>') html += "&gt;";
      else html += Encoding::WideToUtf8(std::wstring(1, ch));
    }
  }
  return Paste(current.window, text + suffix, CharacterCount(current.keyword + current.suffix),
               left < 0 ? 0 : static_cast<size_t>(left) + suffix.size(),
               static_cast<size_t>(characters) + suffix.size(), current.keyword + current.suffix, html);
}

inline bool PasteTextSnippet(HWND target, const std::wstring &text, int left, int characters, const std::string &html) {
  if (left < -1 || characters < 0) return false;
  SnippetInput::Invalidate(true);
  return SnippetInput::Paste(target, text, 0, left < 0 ? 0 : static_cast<size_t>(left), static_cast<size_t>(characters), L"", html);
}

inline bool CopyTextSnippet(const std::wstring &text, const std::string &html) {
  SnippetInput::Invalidate(true);
  return SnippetInput::WriteClipboard(text, html, false);
}

inline bool ExpandTextSnippet() {
  using namespace SnippetInput;
  return Request(std::wstring(buffer.begin(), buffer.end()), L"");
}

inline void InvalidateSnippetRequest() { SnippetInput::Invalidate(false); }

inline bool IsSnippetClipboardSequence(DWORD sequence) {
  return sequence != 0 && (sequence == SnippetInput::temporaryClipboardSequence || sequence == SnippetInput::restoredClipboardSequence);
}

inline void RecordSnippetForeground(HWND window) {
  SnippetInput::Invalidate(true);
  SnippetInput::bufferWindow = window;
  SnippetInput::bufferFocus = SnippetInput::FocusedControl(window);
}

inline void RecordSnippetMouse(WPARAM message, const MSLLHOOKSTRUCT &info) {
  if (info.flags & LLMHF_INJECTED) return;
  if (message == WM_MOUSEMOVE) {
    if (SnippetInput::pending.id || SnippetInput::undoCharacters || SnippetInput::cursorTimer) SnippetInput::Invalidate(false);
  } else if (message == WM_LBUTTONDOWN || message == WM_RBUTTONDOWN || message == WM_MBUTTONDOWN ||
             message == WM_XBUTTONDOWN || message == WM_MOUSEWHEEL || message == WM_MOUSEHWHEEL) {
    SnippetInput::Invalidate(true);
  }
}

// Returns true only when Escape successfully undoes an expansion.
inline bool RecordSnippetKey(WPARAM message, const KBDLLHOOKSTRUCT &key) {
  using namespace SnippetInput;
  if (message != WM_KEYDOWN && message != WM_SYSKEYDOWN) return false;
  const HWND window = GetForegroundWindow();
  const HWND focus = FocusedControl(window);
  if (window != bufferWindow || focus != bufferFocus) { Invalidate(true); bufferWindow = window; bufferFocus = focus; }
  const DWORD vk = key.vkCode;
  if (vk == VK_ESCAPE && Undo()) return true;
  Invalidate(false);
  if (vk == VK_SHIFT || vk == VK_LSHIFT || vk == VK_RSHIFT || vk == VK_CONTROL || vk == VK_LCONTROL ||
      vk == VK_RCONTROL || vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU || vk == VK_LWIN || vk == VK_RWIN) return false;
  const bool altGr = (GetAsyncKeyState(VK_RMENU) & 0x8000) && (GetAsyncKeyState(VK_CONTROL) & 0x8000);
  if ((!altGr && ((GetAsyncKeyState(VK_CONTROL) & 0x8000) || (GetAsyncKeyState(VK_MENU) & 0x8000))) ||
      (GetAsyncKeyState(VK_LWIN) & 0x8000) || (GetAsyncKeyState(VK_RWIN) & 0x8000)) { buffer.clear(); return false; }
  if (vk == VK_BACK) {
    if (!buffer.empty()) {
      const wchar_t tail = buffer.back(); buffer.pop_back();
      if (tail >= 0xDC00 && tail <= 0xDFFF && !buffer.empty()) buffer.pop_back();
    }
    return false;
  }
  if (vk == VK_RETURN || vk == VK_TAB || vk == VK_ESCAPE || vk == VK_DELETE ||
      (vk >= VK_PRIOR && vk <= VK_DOWN)) { buffer.clear(); return false; }
  BYTE state[256] = {};
  GetKeyboardState(state);
  state[VK_SHIFT] = (GetAsyncKeyState(VK_SHIFT) & 0x8000) ? 0x80 : 0;
  state[VK_CONTROL] = altGr ? 0x80 : 0;
  state[VK_MENU] = altGr ? 0x80 : 0;
  state[VK_CAPITAL] = static_cast<BYTE>(GetKeyState(VK_CAPITAL) & 1);
  wchar_t chars[8] = {};
  const HKL layout = GetKeyboardLayout(GetWindowThreadProcessId(window, nullptr));
  const int count = ToUnicodeEx(vk, key.scanCode, state, chars, ARRAYSIZE(chars), 0x4, layout);
  if (count < 0) { buffer.clear(); return false; }
  if (count == 0) return false;
  const std::wstring before(buffer.begin(), buffer.end());
  for (int i = 0; i < count; ++i) if (chars[i] >= L' ') buffer.push_back(chars[i]);
  while (buffer.size() > kBufferMax) buffer.pop_front();
  if (!preferences.autoExpand || snippets.empty()) return false;
  if (preferences.mode == "immediate") Request(std::wstring(buffer.begin(), buffer.end()), L"");
  else if (count == 1 && (iswspace(chars[0]) || iswpunct(chars[0]))) Request(before, std::wstring(1, chars[0]));
  return false;
}

inline void ShutdownTextSnippets() {
  SnippetInput::Invalidate(true);
  if (SnippetInput::restoreTimer) SnippetInput::RestoreClipboard(nullptr, 0, SnippetInput::restoreTimer, 0);
  if (SnippetInput::restoreTimer) KillTimer(nullptr, SnippetInput::restoreTimer);
  SnippetInput::DiscardSavedClipboard();
  SnippetInput::requestExpansion = nullptr;
}

#endif // TABAMEWIN32_TEXT_SNIPPETS
