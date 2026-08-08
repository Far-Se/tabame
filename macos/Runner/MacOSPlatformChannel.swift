import Cocoa
import FlutterMacOS
import ApplicationServices
import CoreGraphics
import UserNotifications
import Security
import Carbon

/// Native macOS bridge for the Phase 5 platform contracts.
///
/// This class intentionally exposes opaque window IDs and neutral dictionaries
/// only. TCC checks, CoreGraphics, Accessibility, LaunchServices, Carbon, and
/// Keychain details stay inside the macOS runner.
final class MacOSPlatformChannel: NSObject, FlutterStreamHandler {
  static let methodChannelName = "tabame/macos/core"
  static let eventChannelName = "tabame/macos/events"
  static private(set) var shared: MacOSPlatformChannel?

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?

  private var clipboardTimer: Timer?
  private var lastClipboardChangeCount: Int = NSPasteboard.general.changeCount

  private var hotKeyRef: EventHotKeyRef?
  private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
  private var hotKeyNames: [UInt32: String] = [:]
  private var hotKeyValues: [UInt32: String] = [:]
  private var hotKeyEventHandler: EventHandlerRef?
  private var hotKeyName = "summon"

  private var capturedFocusPID: pid_t?
  private var savedWindowFrames: [String: (CGPoint, CGSize)] = [:]

  private let keychainService = "com.farse.tabame"
  private let keychainAccount = "master-key-v1"

  private static let hotKeySignature: OSType = 0x54424D45 // TBME

  private init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    super.init()

    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    eventChannel.setStreamHandler(self)
  }

  static func register(messenger: FlutterBinaryMessenger) {
    if shared == nil {
      shared = MacOSPlatformChannel(messenger: messenger)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  deinit {
    stopClipboardPolling()
    unregisterGlobalHotkey()
    if let handler = hotKeyEventHandler {
      RemoveEventHandler(handler)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "permissionStates":
      permissionStates(completion: result)
    case "requestPermission":
      let arguments = call.arguments as? [String: Any] ?? [:]
      requestPermission((arguments["permission"] as? String) ?? "", completion: result)
    case "openPermissionSettings":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(openPermissionSettings(for: (arguments["permission"] as? String) ?? ""))
    case "listWindows":
      result(listWindows())
    case "activateWindow":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(activateWindow(nativeID: (arguments["nativeId"] as? String) ?? ""))
    case "listMonitors":
      result(listMonitors())
    case "cursorMonitor":
      result(cursorMonitor())
    case "placePopup":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(placePopup(arguments: arguments))
    case "cursorPosition":
      result(cursorPosition())
    case "snapWindow":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(snapWindow(arguments: arguments))
    case "restoreWindow":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(restoreWindow(nativeID: (arguments["nativeId"] as? String) ?? ""))
    case "captureFocus":
      result(captureFocus())
    case "restoreFocus":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(restoreFocus(token: arguments["token"] as? String))
    case "registerGlobalHotkeys":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(registerGlobalHotkeys(arguments: arguments))
    case "registerGlobalHotkey":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(registerGlobalHotkey(arguments: arguments))
    case "unregisterGlobalHotkey":
      unregisterGlobalHotkey()
      result(true)
    case "startClipboardMonitoring":
      startClipboardPolling()
      result(true)
    case "stopClipboardMonitoring":
      stopClipboardPolling()
      result(true)
    case "readClipboardText":
      result(NSPasteboard.general.string(forType: .string))
    case "writeClipboardText":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(writeClipboardText((arguments["text"] as? String) ?? ""))
    case "launchApplication":
      let arguments = call.arguments as? [String: Any] ?? [:]
      launchApplication(arguments: arguments, completion: result)
    case "writeApplicationIcon":
      let arguments = call.arguments as? [String: Any] ?? [:]
      result(writeApplicationIcon(arguments: arguments))
    case "ensureKeychainKey":
      result(ensureKeychainKey())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: Permissions

  private func permissionStates(completion: @escaping FlutterResult) {
    let immediate: [[String: Any]] = [
      accessibilityPermissionState(),
      inputMonitoringPermissionState(),
      screenRecordingPermissionState(),
    ]
    UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
      guard let self = self else { return }
      var states = immediate
      states.append(self.notificationPermissionState(settings))
      DispatchQueue.main.async {
        completion(states)
      }
    }
  }

  private func requestPermission(_ permission: String, completion: @escaping FlutterResult) {
    switch permission {
    case "accessibility":
      let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
      _ = AXIsProcessTrustedWithOptions(options)
      permissionStates { value in
        if let states = value as? [[String: Any]],
           let state = states.first(where: { ($0["permission"] as? String) == permission }) {
          completion(state)
        } else {
          completion(self.accessibilityPermissionState())
        }
      }
    case "inputMonitoring":
      if #available(macOS 10.15, *) {
        _ = CGRequestListenEventAccess()
      }
      permissionStates { value in
        if let states = value as? [[String: Any]],
           let state = states.first(where: { ($0["permission"] as? String) == permission }) {
          completion(state)
        } else {
          completion(self.inputMonitoringPermissionState())
        }
      }
    case "screenRecording":
      if #available(macOS 10.15, *) {
        _ = CGRequestScreenCaptureAccess()
      }
      permissionStates { value in
        if let states = value as? [[String: Any]],
           let state = states.first(where: { ($0["permission"] as? String) == permission }) {
          completion(state)
        } else {
          completion(self.screenRecordingPermissionState())
        }
      }
    case "notifications":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
        guard let self = self else { return }
        self.permissionStates { value in
          if let states = value as? [[String: Any]],
             let state = states.first(where: { ($0["permission"] as? String) == permission }) {
            completion(state)
          } else {
            completion(["permission": permission, "status": "unknown"])
          }
        }
      }
    default:
      completion(["permission": permission, "status": "unavailable"])
    }
  }

  private func accessibilityPermissionState() -> [String: Any] {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    return [
      "permission": "accessibility",
      "status": AXIsProcessTrustedWithOptions(options) ? "granted" : "denied",
      "reason": "Required to activate and raise another application's window.",
    ]
  }

  private func inputMonitoringPermissionState() -> [String: Any] {
    let granted: Bool
    if #available(macOS 10.15, *) {
      granted = CGPreflightListenEventAccess()
    } else {
      granted = false
    }
    return [
      "permission": "inputMonitoring",
      "status": granted ? "granted" : "denied",
      "reason": "Required only for low-level input features; Carbon summon shortcuts can still work without it.",
    ]
  }

  private func screenRecordingPermissionState() -> [String: Any] {
    let granted: Bool
    if #available(macOS 10.15, *) {
      granted = CGPreflightScreenCaptureAccess()
    } else {
      granted = false
    }
    return [
      "permission": "screenRecording",
      "status": granted ? "granted" : "denied",
      "reason": "Required for complete window titles and screen capture APIs.",
    ]
  }

  private func notificationPermissionState(_ settings: UNNotificationSettings) -> [String: Any] {
    let status: String
    switch settings.authorizationStatus {
    case .authorized, .provisional:
      status = "granted"
    case .denied:
      status = "denied"
    case .notDetermined:
      status = "notDetermined"
    @unknown default:
      status = "unknown"
    }
    return [
      "permission": "notifications",
      "status": status,
      "reason": "Requested when the first notification is sent.",
    ]
  }

  private func openPermissionSettings(for permission: String) -> Bool {
    let pane: String
    switch permission {
    case "accessibility":
      pane = "Privacy_Accessibility"
    case "inputMonitoring":
      pane = "Privacy_ListenEvent"
    case "screenRecording":
      pane = "Privacy_ScreenCapture"
    case "notifications":
      guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
        return false
      }
      return NSWorkspace.shared.open(url)
    default:
      return false
    }
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
      return false
    }
    return NSWorkspace.shared.open(url)
  }

  // MARK: Windows

  private func listWindows() -> [[String: Any]] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
      return []
    }

    let ownPID = ProcessInfo.processInfo.processIdentifier
    return rawWindows.compactMap { info in
      let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
      if layer != 0 { return nil }
      let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
      let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
      if pid == 0 || windowNumber == 0 { return nil }
      let onScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
      if pid == ownPID { return nil }

      var bounds = CGRect.zero
      if let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
         let converted = CGRect(dictionaryRepresentation: dictionary as CFDictionary) {
        bounds = converted
      }

      let application = NSRunningApplication(processIdentifier: pid)
      let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? application?.localizedName ?? ""
      let title = (info[kCGWindowName as String] as? String) ?? ""
      if ownerName.isEmpty { return nil }
      let cocoaBounds = cocoaRect(fromQuartz: bounds)

      return [
        "nativeId": "\(pid):\(windowNumber)",
        "title": title,
        "applicationName": ownerName,
        "bundleIdentifier": application?.bundleIdentifier ?? "",
        "processId": Int(pid),
        "x": Double(cocoaBounds.origin.x),
        "y": Double(cocoaBounds.origin.y),
        "width": Double(cocoaBounds.size.width),
        "height": Double(cocoaBounds.size.height),
        "isOnScreen": onScreen,
        "isMinimized": false,
        "layer": layer,
      ]
    }
  }

  private func activateWindow(nativeID: String) -> Bool {
    let parts = nativeID.split(separator: ":")
    guard parts.count == 2,
          let pidValue = Int32(String(parts[0])),
          let pid = pid_t(exactly: pidValue),
          let windowNumber = UInt32(String(parts[1])),
          let application = NSRunningApplication(processIdentifier: pid) else {
      return false
    }

    let activated = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    guard AXIsProcessTrusted() else { return activated }

    let windowInfo = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]])?
      .first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowNumber })
    let targetTitle = windowInfo?[kCGWindowName as String] as? String
    let axApplication = AXUIElementCreateApplication(pid)
    var rawWindows: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(axApplication, kAXWindowsAttribute as CFString, &rawWindows)
    guard let axWindows = rawWindows as? [AXUIElement] else { return activated }

    let target = axWindows.first(where: { window in
      guard let targetTitle = targetTitle, !targetTitle.isEmpty else { return true }
      return accessibilityWindowTitle(window) == targetTitle
    })
    if let target = target {
      _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
      _ = AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
      return true
    }
    return activated
  }

  private func accessibilityWindowTitle(_ window: AXUIElement) -> String? {
    var value: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
    return value as? String
  }

  private func cocoaRect(fromQuartz rect: CGRect) -> CGRect {
    // CGWindow bounds use a top-left origin anchored to the primary display;
    // Cocoa screen frames use a bottom-left origin. The primary display height
    // is the stable conversion anchor even when another display is above or
    // below it.
    let desktopTop = NSScreen.screens.first?.frame.maxY ?? rect.maxY
    return CGRect(
      x: rect.origin.x,
      y: desktopTop - rect.maxY,
      width: rect.size.width,
      height: rect.size.height
    )
  }

  // MARK: Monitors and focus

  private func screenIdentifier(_ screen: NSScreen) -> String {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    if let number = screen.deviceDescription[key] as? NSNumber {
      return "display:\(number.uint32Value)"
    }
    let index = NSScreen.screens.enumerated().first(where: { $0.element === screen })?.offset ?? 0
    return "screen:\(index)"
  }

  private func monitorDictionary(_ screen: NSScreen, isPrimary: Bool) -> [String: Any] {
    let frame = screen.frame
    let visible = screen.visibleFrame
    return [
      "nativeId": screenIdentifier(screen),
      "x": Double(frame.origin.x),
      "y": Double(frame.origin.y),
      "width": Double(frame.size.width),
      "height": Double(frame.size.height),
      "visibleX": Double(visible.origin.x),
      "visibleY": Double(visible.origin.y),
      "visibleWidth": Double(visible.size.width),
      "visibleHeight": Double(visible.size.height),
      "scaleFactor": Double(screen.backingScaleFactor),
      "isPrimary": isPrimary,
    ]
  }

  private func listMonitors() -> [[String: Any]] {
    let screens = NSScreen.screens
    return screens.enumerated().map { index, screen in
      monitorDictionary(screen, isPrimary: index == 0)
    }
  }

  private func cursorMonitor() -> [String: Any]? {
    let cursor = NSEvent.mouseLocation
    let screens = NSScreen.screens
    if let index = screens.firstIndex(where: { $0.frame.contains(cursor) }) {
      return monitorDictionary(screens[index], isPrimary: index == 0)
    }
    return screens.first.map { monitorDictionary($0, isPrimary: true) }
  }

  private func placePopup(arguments: [String: Any]) -> [String: Any]? {
    let width = CGFloat((arguments["width"] as? NSNumber)?.doubleValue ?? 0)
    let height = CGFloat((arguments["height"] as? NSNumber)?.doubleValue ?? 0)
    let margin = CGFloat((arguments["margin"] as? NSNumber)?.doubleValue ?? 8)
    guard width > 0, height > 0 else { return nil }

    let requestedID = arguments["monitorId"] as? String
    let screen = NSScreen.screens.first(where: { screenIdentifier($0) == requestedID })
      ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
      ?? NSScreen.main
    guard let screen = screen else { return nil }

    let visible = screen.visibleFrame.insetBy(dx: margin, dy: margin)
    let x = min(max(visible.midX - width / 2, visible.minX), max(visible.minX, visible.maxX - width))
    let y = min(max(visible.midY - height / 2, visible.minY), max(visible.minY, visible.maxY - height))
    return [
      "x": Double(x),
      "y": Double(y),
      "width": Double(width),
      "height": Double(height),
      "monitorId": screenIdentifier(screen),
    ]
  }

  private func cursorPosition() -> [String: Any] {
    let point = NSEvent.mouseLocation
    return [
      "x": Double(point.x),
      "y": Double(point.y),
    ]
  }

  private func snapWindow(arguments: [String: Any]) -> Bool {
    guard AXIsProcessTrusted(),
          let nativeID = arguments["nativeId"] as? String,
          let target = accessibilityWindow(nativeID: nativeID),
          let xValue = (arguments["x"] as? NSNumber)?.doubleValue,
          let yValue = (arguments["y"] as? NSNumber)?.doubleValue,
          let widthValue = (arguments["width"] as? NSNumber)?.doubleValue,
          let heightValue = (arguments["height"] as? NSNumber)?.doubleValue else {
      return false
    }
    let x = CGFloat(xValue)
    let y = CGFloat(yValue)
    let width = CGFloat(widthValue)
    let height = CGFloat(heightValue)
    guard width > 0, height > 0 else { return false }

    if savedWindowFrames[nativeID] == nil, let frame = accessibilityFrame(target) {
      savedWindowFrames[nativeID] = frame
    }

    // NSScreen and the neutral Dart model use Cocoa's bottom-left origin. AX
    // window positions use the Quartz top-left desktop origin, so convert at
    // this native boundary instead of leaking a coordinate-system exception to
    // shared placement code.
    let desktopTop = NSScreen.screens.first?.frame.maxY ?? (y + height)
    var position = CGPoint(x: x, y: desktopTop - y - height)
    var size = CGSize(width: width, height: height)
    guard let positionValue = AXValueCreate(.cgPoint, &position),
          let sizeValue = AXValueCreate(.cgSize, &size) else {
      return false
    }

    let positionResult = AXUIElementSetAttributeValue(
      target,
      kAXPositionAttribute as CFString,
      positionValue
    )
    let sizeResult = AXUIElementSetAttributeValue(
      target,
      kAXSizeAttribute as CFString,
      sizeValue
    )
    return positionResult == .success && sizeResult == .success
  }

  private func restoreWindow(nativeID: String) -> Bool {
    guard AXIsProcessTrusted(),
          let frame = savedWindowFrames[nativeID],
          let target = accessibilityWindow(nativeID: nativeID) else {
      return false
    }

    var position = frame.0
    var size = frame.1
    guard let positionValue = AXValueCreate(.cgPoint, &position),
          let sizeValue = AXValueCreate(.cgSize, &size) else {
      return false
    }
    let positionResult = AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, positionValue)
    let sizeResult = AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, sizeValue)
    let restored = positionResult == .success && sizeResult == .success
    if restored { savedWindowFrames.removeValue(forKey: nativeID) }
    return restored
  }

  private func accessibilityWindow(nativeID: String) -> AXUIElement? {
    let parts = nativeID.split(separator: ":")
    guard parts.count == 2,
          let pidValue = Int32(String(parts[0])),
          let windowNumber = UInt32(String(parts[1])),
          let pid = pid_t(exactly: pidValue) else {
      return nil
    }

    let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]])?
      .first(where: {
        let infoPID = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        let infoNumber = ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        return infoPID == pidValue && infoNumber == windowNumber
      })
    let targetTitle = info?[kCGWindowName as String] as? String
    let application = AXUIElementCreateApplication(pid)
    var rawWindows: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &rawWindows) == .success,
          let windows = rawWindows as? [AXUIElement] else {
      return nil
    }

    return windows.first(where: { window in
      guard let targetTitle = targetTitle, !targetTitle.isEmpty else { return true }
      return accessibilityWindowTitle(window) == targetTitle
    })
  }

  private func accessibilityFrame(_ window: AXUIElement) -> (CGPoint, CGSize)? {
    var rawPosition: CFTypeRef?
    var rawSize: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &rawPosition) == .success,
          AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &rawSize) == .success,
          let rawPosition = rawPosition,
          let rawSize = rawSize,
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID() else {
      return nil
    }

    let positionValue = rawPosition as! AXValue
    let sizeValue = rawSize as! AXValue
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &position),
          AXValueGetValue(sizeValue, .cgSize, &size) else {
      return nil
    }
    return (position, size)
  }

  private func captureFocus() -> String? {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    guard let application = NSWorkspace.shared.frontmostApplication,
          application.processIdentifier != ownPID else {
      return capturedFocusPID.map(String.init)
    }
    capturedFocusPID = application.processIdentifier
    return String(application.processIdentifier)
  }

  private func restoreFocus(token: String?) -> Bool {
    let rawToken = token ?? (capturedFocusPID.map(String.init) ?? "")
    guard let pidValue = Int32(rawToken),
          let pid = pid_t(exactly: pidValue),
          let application = NSRunningApplication(processIdentifier: pid) else {
      return false
    }
    let activated = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    if activated { capturedFocusPID = nil }
    return activated
  }

  // MARK: Global shortcut

  private func registerGlobalHotkey(arguments: [String: Any]) -> [String: Any] {
    let binding: [String: Any] = [
      "key": arguments["key"] as? String ?? "",
      "modifiers": arguments["modifiers"] as? [String] ?? [],
      "name": arguments["name"] as? String ?? "summon",
      "hotkey": arguments["hotkey"] as? String ?? "",
    ]
    return registerGlobalHotkeys(arguments: ["bindings": [binding]])
  }

  private func registerGlobalHotkeys(arguments: [String: Any]) -> [String: Any] {
    guard let rawBindings = arguments["bindings"] as? [[String: Any]], !rawBindings.isEmpty else {
      unregisterGlobalHotkey()
      return [
        "registered": false,
        "permissionRequired": false,
        "reason": "No global hotkey bindings were supplied.",
      ]
    }

    // Validate the complete replacement set before removing an existing set.
    // This keeps a bad persisted binding from taking down the working summon
    // shortcut during a live settings refresh.
    var preparedBindings: [(binding: [String: Any], keyCode: UInt32, modifiers: UInt32)] = []
    for binding in rawBindings {
      guard let key = binding["key"] as? String,
            let keyCode = keyCode(for: key) else {
        return [
          "registered": false,
          "permissionRequired": false,
          "reason": "The requested key is not supported by the macOS adapter.",
        ]
      }
      guard let modifiers = modifierMask(binding["modifiers"] as? [String] ?? []) else {
        return [
          "registered": false,
          "permissionRequired": false,
          "reason": "Left/right-specific or unknown modifier keys are not supported by the macOS adapter.",
        ]
      }
      preparedBindings.append((binding: binding, keyCode: keyCode, modifiers: modifiers))
    }

    unregisterGlobalHotkey()
    if let firstBinding = rawBindings.first,
       let firstName = firstBinding["name"] as? String,
       !firstName.isEmpty {
      hotKeyName = firstName
    } else {
      hotKeyName = "summon"
    }

    guard installHotKeyEventHandler() else {
      return [
        "registered": false,
        "permissionRequired": true,
        "reason": "macOS could not install its global shortcut handler.",
      ]
    }

    for (index, prepared) in preparedBindings.enumerated() {
      let id = UInt32(index + 1)
      let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: id)
      var reference: EventHotKeyRef?
      let status = RegisterEventHotKey(
        prepared.keyCode,
        prepared.modifiers,
        hotKeyID,
        GetApplicationEventTarget(),
        0,
        &reference
      )
      let listeningPermission = CGPreflightListenEventAccess()
      guard status == noErr, let registeredReference = reference else {
        unregisterGlobalHotkey()
        return [
          "registered": false,
          "permissionRequired": !listeningPermission,
          "reason": status == noErr ? "The shortcut is already in use." : "macOS rejected the global shortcut.",
        ]
      }

      hotKeyRefs[id] = registeredReference
      if let bindingName = prepared.binding["name"] as? String, !bindingName.isEmpty {
        hotKeyNames[id] = bindingName
      } else {
        hotKeyNames[id] = "summon"
      }
      hotKeyValues[id] = (prepared.binding["hotkey"] as? String) ?? ""
    }

    return [
      "registered": true,
      "permissionRequired": false,
      "reason": "",
    ]
  }

  private func modifierMask(_ values: [String]) -> UInt32? {
    var modifiers: UInt32 = 0
    for value in values {
      switch value.uppercased() {
      case "CTRL", "CONTROL":
        modifiers |= UInt32(controlKey)
      case "LCTRL", "RCTRL", "LCONTROL", "RCONTROL",
           "LALT", "RALT", "LEFTALT", "RIGHTALT",
           "LSHIFT", "RSHIFT", "LWIN", "RWIN":
        return nil
      case "ALT", "OPTION":
        modifiers |= UInt32(optionKey)
      case "SHIFT":
        modifiers |= UInt32(shiftKey)
      case "WIN", "CMD", "COMMAND":
        modifiers |= UInt32(cmdKey)
      default:
        return nil
      }
    }
    return modifiers
  }

  private func unregisterGlobalHotkey() {
    if let reference = hotKeyRef {
      UnregisterEventHotKey(reference)
      hotKeyRef = nil
    }
    for reference in hotKeyRefs.values {
      UnregisterEventHotKey(reference)
    }
    hotKeyRefs.removeAll()
    hotKeyNames.removeAll()
    hotKeyValues.removeAll()
  }

  private func installHotKeyEventHandler() -> Bool {
    if hotKeyEventHandler != nil { return true }
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData = userData else { return noErr }
        let owner = Unmanaged<MacOSPlatformChannel>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 0)
        if let event = event {
          _ = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
          )
        }
        owner.sendEvent([
          "type": "hotkey",
          "name": owner.hotKeyNames[hotKeyID.id] ?? owner.hotKeyName,
          "hotkey": owner.hotKeyValues[hotKeyID.id] ?? "",
          "phase": "pressed",
          "action": "pressed",
          "timestamp": Int(Date().timeIntervalSince1970 * 1000),
        ])
        return noErr
      },
      1,
      &eventType,
      userData,
      &hotKeyEventHandler
    )
    return status == noErr
  }

  private func keyCode(for key: String) -> UInt32? {
    switch key.uppercased() {
    case "A": return UInt32(kVK_ANSI_A)
    case "B": return UInt32(kVK_ANSI_B)
    case "C": return UInt32(kVK_ANSI_C)
    case "D": return UInt32(kVK_ANSI_D)
    case "E": return UInt32(kVK_ANSI_E)
    case "F": return UInt32(kVK_ANSI_F)
    case "G": return UInt32(kVK_ANSI_G)
    case "H": return UInt32(kVK_ANSI_H)
    case "I": return UInt32(kVK_ANSI_I)
    case "J": return UInt32(kVK_ANSI_J)
    case "K": return UInt32(kVK_ANSI_K)
    case "L": return UInt32(kVK_ANSI_L)
    case "M": return UInt32(kVK_ANSI_M)
    case "N": return UInt32(kVK_ANSI_N)
    case "O": return UInt32(kVK_ANSI_O)
    case "P": return UInt32(kVK_ANSI_P)
    case "Q": return UInt32(kVK_ANSI_Q)
    case "R": return UInt32(kVK_ANSI_R)
    case "S": return UInt32(kVK_ANSI_S)
    case "T": return UInt32(kVK_ANSI_T)
    case "U": return UInt32(kVK_ANSI_U)
    case "V": return UInt32(kVK_ANSI_V)
    case "W": return UInt32(kVK_ANSI_W)
    case "X": return UInt32(kVK_ANSI_X)
    case "Y": return UInt32(kVK_ANSI_Y)
    case "Z": return UInt32(kVK_ANSI_Z)
    case "0": return UInt32(kVK_ANSI_0)
    case "1": return UInt32(kVK_ANSI_1)
    case "2": return UInt32(kVK_ANSI_2)
    case "3": return UInt32(kVK_ANSI_3)
    case "4": return UInt32(kVK_ANSI_4)
    case "5": return UInt32(kVK_ANSI_5)
    case "6": return UInt32(kVK_ANSI_6)
    case "7": return UInt32(kVK_ANSI_7)
    case "8": return UInt32(kVK_ANSI_8)
    case "9": return UInt32(kVK_ANSI_9)
    case "MINUS", "-": return UInt32(kVK_ANSI_Minus)
    case "EQUAL", "=": return UInt32(kVK_ANSI_Equal)
    case "LEFTBRACKET", "[": return UInt32(kVK_ANSI_LeftBracket)
    case "RIGHTBRACKET", "]": return UInt32(kVK_ANSI_RightBracket)
    case "BACKSLASH", "\\": return UInt32(kVK_ANSI_Backslash)
    case "SEMICOLON", ";": return UInt32(kVK_ANSI_Semicolon)
    case "QUOTE", "'": return UInt32(kVK_ANSI_Quote)
    case "COMMA", ",": return UInt32(kVK_ANSI_Comma)
    case "PERIOD", ".": return UInt32(kVK_ANSI_Period)
    case "SLASH", "/": return UInt32(kVK_ANSI_Slash)
    case "GRAVE", "`": return UInt32(kVK_ANSI_Grave)
    case "SPACE": return UInt32(kVK_Space)
    case "RETURN", "ENTER": return UInt32(kVK_Return)
    case "TAB": return UInt32(kVK_Tab)
    case "ESCAPE", "ESC": return UInt32(kVK_Escape)
    case "BACK", "BACKSPACE": return UInt32(kVK_Delete)
    case "DELETE": return UInt32(kVK_ForwardDelete)
    case "INSERT": return UInt32(kVK_Help)
    case "HOME": return UInt32(kVK_Home)
    case "END": return UInt32(kVK_End)
    case "PRIOR", "PAGEUP": return UInt32(kVK_PageUp)
    case "NEXT", "PAGEDOWN": return UInt32(kVK_PageDown)
    case "LEFT": return UInt32(kVK_LeftArrow)
    case "RIGHT": return UInt32(kVK_RightArrow)
    case "UP": return UInt32(kVK_UpArrow)
    case "DOWN": return UInt32(kVK_DownArrow)
    case "NUMPAD0": return UInt32(kVK_ANSI_Keypad0)
    case "NUMPAD1": return UInt32(kVK_ANSI_Keypad1)
    case "NUMPAD2": return UInt32(kVK_ANSI_Keypad2)
    case "NUMPAD3": return UInt32(kVK_ANSI_Keypad3)
    case "NUMPAD4": return UInt32(kVK_ANSI_Keypad4)
    case "NUMPAD5": return UInt32(kVK_ANSI_Keypad5)
    case "NUMPAD6": return UInt32(kVK_ANSI_Keypad6)
    case "NUMPAD7": return UInt32(kVK_ANSI_Keypad7)
    case "NUMPAD8": return UInt32(kVK_ANSI_Keypad8)
    case "NUMPAD9": return UInt32(kVK_ANSI_Keypad9)
    case "NUMPADADD": return UInt32(kVK_ANSI_KeypadPlus)
    case "NUMPADSUBTRACT": return UInt32(kVK_ANSI_KeypadMinus)
    case "NUMPADMULTIPLY": return UInt32(kVK_ANSI_KeypadMultiply)
    case "NUMPADDIVIDE": return UInt32(kVK_ANSI_KeypadDivide)
    case "NUMPADDECIMAL": return UInt32(kVK_ANSI_KeypadDecimal)
    case "F1": return UInt32(kVK_F1)
    case "F2": return UInt32(kVK_F2)
    case "F3": return UInt32(kVK_F3)
    case "F4": return UInt32(kVK_F4)
    case "F5": return UInt32(kVK_F5)
    case "F6": return UInt32(kVK_F6)
    case "F7": return UInt32(kVK_F7)
    case "F8": return UInt32(kVK_F8)
    case "F9": return UInt32(kVK_F9)
    case "F10": return UInt32(kVK_F10)
    case "F11": return UInt32(kVK_F11)
    case "F12": return UInt32(kVK_F12)
    case "F13": return UInt32(kVK_F13)
    case "F14": return UInt32(kVK_F14)
    case "F15": return UInt32(kVK_F15)
    case "F16": return UInt32(kVK_F16)
    case "F17": return UInt32(kVK_F17)
    case "F18": return UInt32(kVK_F18)
    case "F19": return UInt32(kVK_F19)
    case "F20": return UInt32(kVK_F20)
    default: return nil
    }
  }

  // MARK: Clipboard

  private func startClipboardPolling() {
    if clipboardTimer != nil { return }
    lastClipboardChangeCount = NSPasteboard.general.changeCount
    clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.pollClipboard()
    }
  }

  private func stopClipboardPolling() {
    clipboardTimer?.invalidate()
    clipboardTimer = nil
  }

  private func pollClipboard() {
    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount
    guard changeCount != lastClipboardChangeCount else { return }
    lastClipboardChangeCount = changeCount
    guard let text = pasteboard.string(forType: .string) else { return }
    sendEvent([
      "type": "clipboardChanged",
      "text": text,
      "changeCount": changeCount,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
    ])
  }

  private func writeClipboardText(_ text: String) -> Bool {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
  }

  private func sendEvent(_ value: [String: Any]) {
    guard let eventSink = eventSink else { return }
    DispatchQueue.main.async {
      eventSink(value)
    }
  }

  // MARK: Applications and icons

  private func launchApplication(arguments: [String: Any], completion: @escaping FlutterResult) {
    let workspace = NSWorkspace.shared
    var applicationURL: URL?
    if let bundleIdentifier = arguments["bundleIdentifier"] as? String,
       !bundleIdentifier.isEmpty {
      applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
    if applicationURL == nil,
       let path = arguments["path"] as? String,
       !path.isEmpty {
      applicationURL = URL(fileURLWithPath: path)
    }
    guard let url = applicationURL else {
      completion(false)
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    workspace.openApplication(at: url, configuration: configuration) { application, error in
      DispatchQueue.main.async {
        completion(application != nil && error == nil)
      }
    }
  }

  private func writeApplicationIcon(arguments: [String: Any]) -> Bool {
    guard let path = arguments["path"] as? String,
          let destinationPath = arguments["destinationPath"] as? String,
          !path.isEmpty,
          !destinationPath.isEmpty else {
      return false
    }
    let image = NSWorkspace.shared.icon(forFile: path)
    image.size = NSSize(width: 128, height: 128)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
      return false
    }
    do {
      let destination = URL(fileURLWithPath: destinationPath)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try png.write(to: destination, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  // MARK: Keychain

  private func ensureKeychainKey() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let readStatus = SecItemCopyMatching(query as CFDictionary, &item)
    if readStatus == errSecSuccess,
       let data = item as? Data,
       data.count == 32 {
      return data.base64EncodedString()
    }

    let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: key,
    ]
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return key.base64EncodedString()
    }
    if addStatus == errSecDuplicateItem {
      var existing: CFTypeRef?
      if SecItemCopyMatching(query as CFDictionary, &existing) == errSecSuccess,
         let data = existing as? Data,
         data.count == 32 {
        return data.base64EncodedString()
      }
    }
    return nil
  }
}
