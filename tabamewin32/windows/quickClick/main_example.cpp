// ---------------------------------------------------------------------------
// main_example.cpp  –  Integration example showing all configurable keys
//
// Build (MSVC):
//   cl /std:c++17 /EHsc main_example.cpp QuickClickController.cpp
//      /link Shcore.lib User32.lib
//
// Build (MinGW / g++):
//   g++ -std=c++17 -o quickClick.exe main_example.cpp QuickClickController.cpp
//       -lShcore -lUser32
// ---------------------------------------------------------------------------

#include "QuickClickController.h"
#include <iostream>

int example()
{
    QuickClickConfig cfg;

    // --- Grid keys ---
    cfg.horizontalKeys = { '1','2','3','4','5','6','7','8','9' };
    cfg.verticalKeys   = { 'q','w','e','r','t','y','u','i','o' };

    // --- Nudge ---
    cfg.nudgeAmount = 5;

    // --- Action keys (all configurable) ---
    //
    // Default layout (mirrors the original QuickClick behaviour):
    //   Ctrl        = left click / double click (same key, tap vs double-tap)
    //   Alt (hold)  = drag
    //   Alt (tap)   = (absorbed by drag; assign a different key for right click)
    cfg.leftClickKey   = VK_CONTROL;  // tap  → left click
    cfg.doubleClickKey = VK_CONTROL;  // double-tap → double click (same key = detection active)
    cfg.dragKey        = VK_MENU;     // hold → drag
    cfg.rightClickKey  = VK_MENU;     // when equal to dragKey, right-click is subsumed by drag

    // Example: separate right-click onto its own key so Alt-hold = drag
    // AND a dedicated right-click key both work independently:
    //   cfg.rightClickKey = VK_F2;   // F2 = instant right click
    //   cfg.dragKey       = VK_MENU; // Alt (hold) = drag, unrelated to right-click

    // Example: put double-click on its own key (fires immediately, no timer):
    //   cfg.leftClickKey   = VK_CONTROL; // Ctrl = left click (instant)
    //   cfg.doubleClickKey = VK_F3;      // F3   = double click (instant)

    cfg.doubleClickThresholdMs = 400;

    // --- Extra arrow bindings ---
    cfg.extraArrowBindings["up"]    = { 'W' };
    cfg.extraArrowBindings["down"]  = { 'S' };
    cfg.extraArrowBindings["left"]  = { 'A' };
    cfg.extraArrowBindings["right"] = { 'D' };

    // --- Scroll keys ---
    cfg.scrollUpKey    = VK_OEM_4;   // [
    cfg.scrollDownKey  = VK_OEM_6;   // ]
    cfg.scrollLeftKey  = VK_OEM_1;   // ;
    cfg.scrollRightKey = VK_OEM_7;   // '
    cfg.scrollDelta    = WHEEL_DELTA;

    // -----------------------------------------------------------------------
    QuickClickController controller(cfg);
    controller.Start();

    // Register toggle (F6) and quit (F12) hotkeys on the main thread.
    RegisterHotKey(nullptr, 1, 0, VK_F6);
    RegisterHotKey(nullptr, 2, 0, VK_F12);

    std::cout << "QuickClick running.\n"
              << "  F6  = toggle active / inactive\n"
              << "  F12 = quit\n\n"
              << "Action key defaults:\n"
              << "  Ctrl (tap)         = left click\n"
              << "  Ctrl (double-tap)  = double click\n"
              << "  Alt (hold)         = drag\n"
              << "  [  ]  ;  '         = scroll\n";

    MSG msg{};
    while (GetMessageW(&msg, nullptr, 0, 0))
    {
        if (msg.message == WM_HOTKEY)
        {
            if (msg.wParam == 1)
            {
                bool now = !controller.IsActive();
                controller.SetActive(now);
                std::cout << (now ? "[ON]  intercepting keys\n" : "[OFF] passthrough\n");
            }
            else if (msg.wParam == 2)
            {
                PostQuitMessage(0);
            }
        }
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }

    UnregisterHotKey(nullptr, 1);
    UnregisterHotKey(nullptr, 2);
    controller.Stop();
    return 0;
}

// ===========================================================================
// ACTION KEY BEHAVIOUR SUMMARY
// ===========================================================================
//
//  leftClickKey == doubleClickKey  (default, same VK)
//    Single tap  → left click  (fired on key-up after threshold expires)
//    Double-tap  → double click (fired on second key-down within threshold)
//
//  leftClickKey != doubleClickKey  (separate VKs)
//    leftClickKey  key-down → left click  (immediate, no timer)
//    doubleClickKey key-down → double click (immediate, no timer)
//
//  dragKey == rightClickKey  (default, same VK)
//    Hold → drag (LEFTDOWN on key-down, LEFTUP on key-up)
//    Right-click is absorbed; assign a different VK to rightClickKey
//    if you want an independent right-click action.
//
//  dragKey != rightClickKey  (separate VKs)
//    dragKey hold        → drag
//    rightClickKey tap   → right click (immediate on key-down)
// ===========================================================================
