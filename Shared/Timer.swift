
import Foundation

final class Timer {

	private let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)

	init(repeats: Bool, interval: TimeInterval, block: @escaping Completion) {

		if repeats {
			timer.scheduleRepeating(deadline: .now() + interval, interval: interval)
		} else {
			timer.scheduleOneshot(deadline: .now() + interval)
		}
		timer.setEventHandler(handler: block)
		timer.resume()
	}

	deinit {
		timer.cancel()
	}
}
