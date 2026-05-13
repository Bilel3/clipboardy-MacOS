import AppKit

// Entry point: run the app
NSApplication.shared.setActivationPolicy(.accessory)
let _delegate = AppDelegate()
NSApplication.shared.delegate = _delegate
NSApplication.shared.run()
