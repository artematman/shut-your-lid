import AppKit
import LidModeFeature
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
 let model = LidModeModel(system: .live(), preferences: .standard)
 var menu: LidModeMenuBar?
 var quitting = false
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.accessory)
  // Load the bundled artwork directly rather than a cached Launch Services icon.
  if let iconURL = Bundle.main.url(forResource: "ShutYourLidLips", withExtension: "icns"),
     let icon = NSImage(contentsOf: iconURL) {
   NSApp.applicationIconImage = icon
  }
  installEditingMenu()
  menu = LidModeMenuBar(model: model); menu?.start()
  // Launch plays the brand splash; it ends in the menu bar icon, not an open panel.
  Task { @MainActor in await Task.yield(); menu?.showBrandSplash() }
 }
 private func installEditingMenu() {
  let main = NSMenu()
  let editItem = NSMenuItem()
  let edit = NSMenu(title: loc("edit.menu"))
  for (title, action, key) in [
   (loc("edit.cut"), #selector(NSText.cut(_:)), "x"),
   (loc("edit.copy"), #selector(NSText.copy(_:)), "c"),
   (loc("edit.paste"), #selector(NSText.paste(_:)), "v"),
   (loc("edit.selectAll"), #selector(NSText.selectAll(_:)), "a")
  ] { edit.addItem(withTitle: title, action: action, keyEquivalent: key) }
  editItem.submenu = edit
  main.addItem(editItem)
  NSApp.mainMenu = main
 }
 func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
  menu?.showBrandSplash()
  return false
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  if quitting { return .terminateNow }
  quitting = true
  Task { await model.prepareToQuit(); NSApp.reply(toApplicationShouldTerminate: true) }
  return .terminateLater
 }
}
@main struct ShutYourLidApp {
 @MainActor static func main() {
  let app = NSApplication.shared
  let delegate = AppDelegate()
  app.delegate = delegate
  withExtendedLifetime(delegate) { app.run() }
 }
}
