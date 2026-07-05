#ifndef TABAMEWIN32_TEXT_SNIPPETS
#define TABAMEWIN32_TEXT_SNIPPETS

#include <deque>
#include <string>
#include <vector>
#include <windows.h>

// ---------------------------------------------------------------------------
// Text Expander / Snippets
//
// The low-level keyboard hook feeds every real (non-injected) keystroke into a
// rolling buffer of the most recent printable characters. When the user fires
// the customizable "insert snippet" hotkey, Dart calls ExpandTextSnippet():
// the longest snippet trigger that is a suffix of the buffer is deleted (via
// synthetic backspaces) and replaced by its expansion (via synthetic Unicode
// input).
//
// Everything here runs on the Flutter platform thread — the same thread that
// owns the LL keyboard hook (RecordSnippetKey) and that services method-channel
// calls (SetTextSnippets / ExpandTextSnippet) — so no locking is needed.
// ---------------------------------------------------------------------------

// A single expansion rule: type `trigger`, fire the hotkey, get `text`.
struct TextSnippet {
  std::wstring trigger;
  std::wstring text;
};

// Keep the buffer short — snippet triggers are abbreviations, not paragraphs.
static constexpr size_t kSnippetBufferMax = 20;
static std::deque<wchar_t> g_snippetBuffer;
static std::vector<TextSnippet> g_snippets;

inline void SetTextSnippets(std::vector<TextSnippet> snippets) {
  g_snippets = std::move(snippets);
}

namespace {

// Keys that move the caret away from the buffered tail; recording past them
// would risk expanding text the caret is no longer sitting after.
bool IsSnippetNavigationKey(DWORD vk) {
  switch (vk) {
  case VK_RETURN:
  case VK_ESCAPE:
  case VK_TAB:
  case VK_LEFT:
  case VK_RIGHT:
  case VK_UP:
  case VK_DOWN:
  case VK_HOME:
  case VK_END:
  case VK_PRIOR:
  case VK_NEXT:
  case VK_DELETE:
    return true;
  default:
    return false;
  }
}

void SendUnicodeText(const std::wstring &text) {
  std::vector<INPUT> inputs;
  inputs.reserve(text.size() * 2);
  for (wchar_t ch : text) {
    if (ch == L'\r')
      continue;
    if (ch == L'\n') {
      // KEYEVENTF_UNICODE '\n' is swallowed by most edit controls; use the
      // real Return key so multi-line snippets actually break lines.
      INPUT down = {};
      down.type = INPUT_KEYBOARD;
      down.ki.wVk = VK_RETURN;
      INPUT up = down;
      up.ki.dwFlags = KEYEVENTF_KEYUP;
      inputs.push_back(down);
      inputs.push_back(up);
      continue;
    }
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wScan = static_cast<WORD>(ch);
    down.ki.dwFlags = KEYEVENTF_UNICODE;
    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
  }
  if (!inputs.empty())
    SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
}

void SendBackspaces(size_t count) {
  if (count == 0)
    return;
  std::vector<INPUT> inputs;
  inputs.reserve(count * 2);
  for (size_t i = 0; i < count; ++i) {
    INPUT down = {};
    down.type = INPUT_KEYBOARD;
    down.ki.wVk = VK_BACK;
    INPUT up = down;
    up.ki.dwFlags = KEYEVENTF_KEYUP;
    inputs.push_back(down);
    inputs.push_back(up);
  }
  SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
}

// The insert-snippet hotkey usually carries a modifier (Ctrl/Alt/...). By the
// time expansion runs those modifiers may still be physically held, which would
// turn our backspaces into Ctrl+Backspace etc. Release whatever is down; the
// user's eventual physical release just sends a harmless extra key-up.
void ReleaseHeldModifiers() {
  static const WORD mods[] = {VK_LCONTROL, VK_RCONTROL, VK_CONTROL, VK_LMENU,
                              VK_RMENU,    VK_MENU,     VK_LSHIFT,  VK_RSHIFT,
                              VK_SHIFT,    VK_LWIN,     VK_RWIN};
  std::vector<INPUT> inputs;
  for (WORD vk : mods) {
    if (!(GetAsyncKeyState(vk) & 0x8000))
      continue;
    INPUT up = {};
    up.type = INPUT_KEYBOARD;
    up.ki.wVk = vk;
    up.ki.dwFlags = KEYEVENTF_KEYUP;
    inputs.push_back(up);
  }
  if (!inputs.empty())
    SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT));
}

} // namespace

// Record a real key-down into the rolling buffer. Skips anything chorded with
// Ctrl/Alt/Win (those are shortcuts, not text — this also keeps the insert
// hotkey combo out of the buffer). Backspace pops the tail; navigation keys
// reset the buffer. Injected keystrokes never reach here (the hook filters
// LLKHF_INJECTED first), so our own expansions don't feed back in.
inline void RecordSnippetKey(WPARAM wParam, const KBDLLHOOKSTRUCT &keyInfo) {
  if (wParam != WM_KEYDOWN && wParam != WM_SYSKEYDOWN)
    return;

  const DWORD vk = keyInfo.vkCode;
  if (vk == VK_BACK) {
    if (!g_snippetBuffer.empty())
      g_snippetBuffer.pop_back();
    return;
  }
  if (IsSnippetNavigationKey(vk)) {
    g_snippetBuffer.clear();
    return;
  }

  // Ignore command chords — only plain (optionally Shift-ed) text is buffered.
  if ((GetAsyncKeyState(VK_CONTROL) & 0x8000) ||
      (GetAsyncKeyState(VK_MENU) & 0x8000) ||
      (GetAsyncKeyState(VK_LWIN) & 0x8000) ||
      (GetAsyncKeyState(VK_RWIN) & 0x8000))
    return;

  // Build a keyboard state good enough for correct case/symbol translation.
  // GetKeyboardState is unreliable for the just-pressed key inside an LL hook,
  // so drive Shift from the async state and read the CapsLock toggle directly.
  BYTE keyboardState[256] = {};
  GetKeyboardState(keyboardState);
  keyboardState[VK_SHIFT] = (GetAsyncKeyState(VK_SHIFT) & 0x8000) ? 0x80 : 0;
  keyboardState[VK_LSHIFT] = (GetAsyncKeyState(VK_LSHIFT) & 0x8000) ? 0x80 : 0;
  keyboardState[VK_RSHIFT] = (GetAsyncKeyState(VK_RSHIFT) & 0x8000) ? 0x80 : 0;
  keyboardState[VK_CAPITAL] =
      static_cast<BYTE>(GetKeyState(VK_CAPITAL) & 0x0001);

  wchar_t chars[8] = {};
  const HKL layout =
      GetKeyboardLayout(GetWindowThreadProcessId(GetForegroundWindow(), nullptr));
  // wFlags bit 0x4 (Windows 10 1607+) keeps ToUnicodeEx from mutating the
  // kernel keyboard state, so dead-key/IME composition in the target app is
  // unaffected by this passive logging.
  const int count = ToUnicodeEx(vk, keyInfo.scanCode, keyboardState, chars,
                                ARRAYSIZE(chars), 0x4, layout);
  if (count <= 0) {
    // Dead key (<0) starts a composed char we can't track here; drop the buffer
    // to avoid a false match. Non-producing key (0) is simply ignored.
    if (count < 0)
      g_snippetBuffer.clear();
    return;
  }

  for (int i = 0; i < count; ++i) {
    if (chars[i] == L'\b')
      continue;
    g_snippetBuffer.push_back(chars[i]);
  }
  while (g_snippetBuffer.size() > kSnippetBufferMax)
    g_snippetBuffer.pop_front();
}

// Match the longest trigger that is a suffix of the buffer, delete it, and type
// the expansion. Returns true if something was expanded.
inline bool ExpandTextSnippet() {
  if (g_snippetBuffer.empty() || g_snippets.empty())
    return false;

  const std::wstring buffer(g_snippetBuffer.begin(), g_snippetBuffer.end());

  const TextSnippet *best = nullptr;
  for (const TextSnippet &snippet : g_snippets) {
    if (snippet.trigger.empty() || snippet.trigger.size() > buffer.size())
      continue;
    const size_t offset = buffer.size() - snippet.trigger.size();
    if (buffer.compare(offset, snippet.trigger.size(), snippet.trigger) != 0)
      continue;
    if (best == nullptr || snippet.trigger.size() > best->trigger.size())
      best = &snippet;
  }
  if (best == nullptr)
    return false;

  const size_t triggerLen = best->trigger.size();
  const std::wstring expansion = best->text;

  ReleaseHeldModifiers();
  SendBackspaces(triggerLen);
  SendUnicodeText(expansion);

  // Keep the buffer in sync with the edit: trigger removed, expansion appended.
  for (size_t i = 0; i < triggerLen && !g_snippetBuffer.empty(); ++i)
    g_snippetBuffer.pop_back();
  for (wchar_t ch : expansion) {
    if (ch == L'\r' || ch == L'\n') {
      g_snippetBuffer.clear();
      continue;
    }
    g_snippetBuffer.push_back(ch);
  }
  while (g_snippetBuffer.size() > kSnippetBufferMax)
    g_snippetBuffer.pop_front();

  return true;
}

#endif // TABAMEWIN32_TEXT_SNIPPETS
