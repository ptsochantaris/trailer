import Foundation

final class TrailerTimer {
    private let timer: DispatchSourceTimer

    init(interval: TimeInterval, block: @escaping () -> Void) {
        timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler(handler: block)
        timer.resume()
    }

    deinit {
        timer.cancel()
    }
}

final class PopTimer {
    private var popTimer: TrailerTimer?
    private let timeInterval: TimeInterval
    private let callback: () -> Void

    func push() {
        popTimer = TrailerTimer(interval: timeInterval) { [weak self] in
            self?.abort()
            self?.callback()
        }
    }

    func abort() {
        popTimer = nil
    }

    var isRunning: Bool {
        popTimer != nil
    }

    init(timeInterval: TimeInterval, callback: @escaping () -> Void) {
        self.timeInterval = timeInterval
        self.callback = callback
    }
}
