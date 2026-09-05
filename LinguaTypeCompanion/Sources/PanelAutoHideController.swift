import Foundation

protocol PanelTimerToken: AnyObject {
    func cancel()
}

protocol PanelTimerScheduling: AnyObject {
    var now: TimeInterval { get }
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> PanelTimerToken
}

private final class RunLoopTimerToken: PanelTimerToken {
    private var timer: Timer?
    init(timer: Timer) { self.timer = timer }
    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}

final class MainRunLoopPanelScheduler: PanelTimerScheduling {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> PanelTimerToken {
        let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return RunLoopTimerToken(timer: timer)
    }
}

final class PanelAutoHideController {
    private let interval: TimeInterval
    private let scheduler: PanelTimerScheduling
    private var token: PanelTimerToken?
    private var deadline: TimeInterval = 0
    private var remaining: TimeInterval = 0
    private var action: (() -> Void)?

    init(interval: TimeInterval = 12, scheduler: PanelTimerScheduling = MainRunLoopPanelScheduler()) {
        self.interval = interval
        self.scheduler = scheduler
    }

    func start(_ action: @escaping () -> Void) {
        cancel()
        self.action = action
        remaining = interval
        scheduleRemaining()
    }

    func pointerEntered() {
        guard token != nil else { return }
        remaining = max(0, deadline - scheduler.now)
        token?.cancel()
        token = nil
    }

    func pointerExited() {
        guard token == nil, action != nil, remaining > 0 else { return }
        scheduleRemaining()
    }

    func cancel() {
        token?.cancel()
        token = nil
        action = nil
        remaining = 0
    }

    private func scheduleRemaining() {
        deadline = scheduler.now + remaining
        token = scheduler.schedule(after: remaining) { [weak self] in
            guard let self else { return }
            self.token = nil
            let action = self.action
            self.action = nil
            self.remaining = 0
            action?()
        }
    }
}
