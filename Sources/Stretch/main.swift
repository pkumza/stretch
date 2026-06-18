import AppKit

// Entry point. Runs as an "accessory" app: no Dock icon, lives in the menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
