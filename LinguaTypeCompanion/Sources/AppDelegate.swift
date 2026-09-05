import Cocoa
import ApplicationServices

final class LinguaTypeAppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController!
    private var panel: TranslationPanel!
    private var coordinator: LearningCoordinator!
    private var observer: TranslationObserver!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Establish an Aqua accessory-app connection before creating windows.
        // LaunchAgents can otherwise start us before NSScreen.main is ready.
        NSApp.setActivationPolicy(.accessory)

        // The learning coordinator owns the floating panel UI and the
        // Apple Translation bridge. AppDelegate hands it the panel so we
        // can show/hide from a single place.
        coordinator = LearningCoordinator.shared

        panel = TranslationPanel(coordinator: coordinator)
        coordinator.attach(panel: panel)

        statusBar = StatusBarController(
            togglePanel: { [weak self] in self?.panel.toggleAttachedToMouse() },
            showPanel:   { [weak self] in self?.panel.showAttachedToMouse() },
            hidePanel:   { [weak self] in self?.panel.hide() },
            isPanelVisible: { [weak self] in self?.panel.isVisible ?? false }
        )

        observer = TranslationObserver(coordinator: coordinator) { [weak self] anchor in
            guard let self else { return }
            // Park the panel near the caret rect that AX gave us. Falls back
            // to current mouse location when the text field has no rect.
            self.panel.position(near: anchor)
        }

        statusBar.install()
        panel.hide()
        observer.start()

        // Make sure the app actually shows itself. Without this, launchd's
        // ProcessType=Background runs don't get a real Aqua handshake and
        // NSStatusBar items stay invisible.
        NSApp.activate(ignoringOtherApps: true)
        NSLog("LinguaType Companion: launched. statusItem installed at \(statusBar.installPath). PID=\(ProcessInfo.processInfo.processIdentifier)")

        // Ask for Accessibility permission the first time the app runs.
        // Without it, AXUIElementCopyAttributeValue returns nil for every
        // attribute on every element and the panel never has data.
        requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        observer?.stop()
    }

    private func requestAccessibilityIfNeeded() {
        let trusted = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)
        if !trusted {
            // The system will show its own consent UI; we can't bypass it.
            NSLog("LinguaType: Accessibility not yet granted. Open System Settings -> Privacy & Security -> Accessibility and enable LinguaType Companion.")
        }
    }
}
