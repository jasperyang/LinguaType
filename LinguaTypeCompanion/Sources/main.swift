// LinguaType Companion entry point.
//
// Runs as a menu bar accessory (no Dock icon). Uses the macOS Accessibility
// API to observe the focused text field; whenever committed Chinese text
// appears there, it asks Apple Translation for a learning overlay and shows
// it in a floating NSPanel.
//
// This is the B-path: LinguaType does NOT register as an input method on
// macOS 26 (TIS auto-registration of third-party IMK apps is silently dropped
// for ad-hoc / non-notarized bundles). Instead, whatever IME the user picks
// — Squirrel, SCIM ITABC, Baidu, etc. — feeds text into the focused field,
// and LinguaType Companion reads it back via AXUIElementCopyAttributeValue.

import Cocoa

let app = NSApplication.shared
let delegate = LinguaTypeAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()