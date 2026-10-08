#!/usr/bin/env swift
// PC-055: Live, explicitly invoked macOS accessibility QA for Pixel Companion.
// No screenshots, prompts, credentials, filesystem changes or provider calls.
// Usage: open the app's menu-bar popover, then
//   swift scripts/quality/verify_live_accessibility.swift <PID> --exercise-tabs
// --exercise-tabs ONLY activates the four read-only navigation buttons.
import AppKit
import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var result: AnyObject?
    guard AXUIElementCopyAttributeValue(
        element, name as CFString, &result
    ) == .success else { return nil }
    return result
}

func inspect(
    _ element: AXUIElement,
    depth: Int,
    tabs: inout [String: AXUIElement]
) {
    guard depth <= 18 else { return }
    if let identifier = attribute(element, "AXIdentifier") as? String,
       identifier.hasPrefix("companion.tab.") {
        tabs[identifier] = element
    }
    if let children = attribute(element, "AXChildren") as? [AXUIElement] {
        for child in children.prefix(100) {
            inspect(child, depth: depth + 1, tabs: &tabs)
        }
    }
}

func inspectRoot(_ app: AXUIElement, tabs: inout [String: AXUIElement]) {
    inspect(app, depth: 0, tabs: &tabs)
    for key in ["AXMenuBar", "AXFocusedUIElement"] {
        if let raw = attribute(app, key) {
            inspect(raw as! AXUIElement, depth: 0, tabs: &tabs)
        }
    }
    if let windows = attribute(app, "AXWindows") as? [AXUIElement] {
        for window in windows {
            inspect(window, depth: 0, tabs: &tabs)
        }
    }
}

let arguments = CommandLine.arguments
let exercise = arguments.contains("--exercise-tabs")
guard arguments.count == (exercise ? 3 : 2),
      let pid = Int32(arguments[1]),
      pid > 0 else {
    print("PC055_AX: INVALID_ARGUMENTS")
    exit(2)
}
guard AXIsProcessTrusted() else {
    print("PC055_AX: ACCESSIBILITY_PERMISSION_REQUIRED")
    exit(3)
}

let app = AXUIElementCreateApplication(pid)
var tabs: [String: AXUIElement] = [:]
inspectRoot(app, tabs: &tabs)
let expected: [(String, String)] = [
    ("overview", "Overview tab"),
    ("agents", "Agents tab"),
    ("usage", "Usage tab"),
    ("activity", "Activity tab")
]
guard expected.allSatisfy({
    tabs["companion.tab." + $0.0] != nil
}) else {
    print("PC055_AX: POPOVER_NOT_VISIBLE_OR_TABS_MISSING")
    exit(4)
}

for (id, expectedDescription) in expected {
    let control = tabs["companion.tab." + id]!
    let description = attribute(control, "AXDescription") as? String
    guard description == expectedDescription else {
        print("PC055_AX: MISSING_SEMANTIC_LABEL_" + id.uppercased())
        exit(5)
    }
    let selection = attribute(control, "AXValue") as? String
    guard selection == "Selected" || selection == "Not selected" else {
        print("PC055_AX: MISSING_SELECTION_VALUE_" + id.uppercased())
        exit(6)
    }
    print("PC055_AX_LABEL_" + id.uppercased() + ": PASS")
}

if exercise {
    for (id, _) in expected {
        let control = tabs["companion.tab." + id]!
        guard AXUIElementPerformAction(
            control, "AXPress" as CFString
        ) == .success else {
            print("PC055_AX_PRESS_" + id.uppercased() + ": FAIL")
            exit(7)
        }
        Thread.sleep(forTimeInterval: 0.15)
        guard attribute(control, "AXValue") as? String == "Selected" else {
            print("PC055_AX_SELECTION_" + id.uppercased() + ": FAIL")
            exit(8)
        }
        print("PC055_AX_PRESS_" + id.uppercased() + ": PASS")
    }
}
print("PC055_AX: PASS (semantic labels and selected state)")
print("VOICEOVER_SPOKEN_AUDIO: NOT_TESTED")
print("KEYBOARD_ONLY_NAVIGATION: NOT_TESTED")
