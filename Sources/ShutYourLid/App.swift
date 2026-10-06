import AppKit
import LidModeFeature
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
 let model = LidModeModel(system: .live())
 var menu: LidModeMenuBar?
 var quitting = false
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.accessory)
  menu = LidModeMenuBar(model: model); menu?.start()
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  if quitting { return .terminateNow }
  quitting = true
  Task { await model.setEnabled(false); NSApp.reply(toApplicationShouldTerminate: true) }
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
