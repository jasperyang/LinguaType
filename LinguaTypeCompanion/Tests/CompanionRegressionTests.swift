import ApplicationServices
import Cocoa
import Foundation

@main
enum CompanionRegressionTests {
    private static var failures = 0

    static func main() {
        _ = NSApplication.shared

        LearningModelsTests.run()
        MenuBarTests.run()
        VocabularyExtractorTests.run()

        testLoadingStateShowsPanel()
        testTranslationBridgeIsInstalledInPanel()
        testAccessibilityBoundsDecodeIntoAppKitCoordinates()
        testApplicationLaunchStartsTextObservation()

        if failures == 0 && Test.failures == 0 {
            print("PASS: Companion regression tests")
        } else {
            print("FAIL: \(failures + Test.failures) Companion regression test(s)")
            exit(1)
        }
    }

    private static func testLoadingStateShowsPanel() {
        let coordinator = LearningCoordinator.shared
        let panel = TranslationPanel(coordinator: coordinator)
        coordinator.attach(panel: panel)

        coordinator.commit(text: "你好世界")
        expect(panel.isVisible, "loading Chinese text makes the learning panel visible")

        coordinator.idle()
        expect(!panel.isVisible, "idle state hides the learning panel")
    }

    private static func testTranslationBridgeIsInstalledInPanel() {
        let coordinator = LearningCoordinator.shared
        _ = TranslationPanel(coordinator: coordinator)

        let bridgeHost = reflectedChild(named: "bridgeHost", in: coordinator)
            .flatMap(unwrapOptional)
        let hostView = bridgeHost as? NSView
        expect(hostView?.superview != nil,
               "Apple Translation host is attached to a live panel view")
    }

    private static func testAccessibilityBoundsDecodeIntoAppKitCoordinates() {
        var accessibilityRect = CGRect(x: 200, y: 300, width: 420, height: 24)
        guard let value = AXValueCreate(.cgRect, &accessibilityRect) else {
            expect(false, "test fixture creates an AX CGRect value")
            return
        }
        let screen = LinguaTypeScreenCoordinateSpace(
            accessibilityFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            appKitFrame: NSRect(x: 0, y: 0, width: 1512, height: 982)
        )

        let decoded = LinguaTypeWindowGeometry.appKitRect(
            fromAXValue: value,
            coordinateSpaces: [screen]
        )
        expect(decoded == NSRect(x: 200, y: 658, width: 420, height: 24),
               "AX top-left bounds convert to AppKit bottom-left coordinates")
    }

    private static func testApplicationLaunchStartsTextObservation() {
        let appDelegate = LinguaTypeAppDelegate()
        appDelegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let observer = reflectedChild(named: "observer", in: appDelegate)
            .flatMap(unwrapOptional)
        let timer = observer
            .flatMap { reflectedChild(named: "timer", in: $0) }
            .flatMap(unwrapOptional) as? Timer
        expect(timer?.isValid == true,
               "application launch starts the focused-text observer")

        let statusBar = reflectedChild(named: "statusBar", in: appDelegate)
            .flatMap(unwrapOptional)
        let installPath = statusBar
            .flatMap { reflectedChild(named: "installPath", in: $0) } as? String
        expect(installPath == "macOS menu bar NSStatusItem",
               "application launch installs controls in the native menu bar")

        appDelegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
    }

    private static func reflectedChild(named name: String, in value: Any) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    private static func expect(_ condition: @autoclosure () -> Bool,
                               _ message: String) {
        if condition() {
            print("PASS: \(message)")
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}
