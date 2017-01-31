
import Foundation

final class Timer {

	private let timer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.main)
	private let completion: Completion

	init(repeats: Bool, interval: TimeInterval, block: @escaping Completion) {
		completion = block

		if repeats {
			timer.scheduleRepeating(deadline: .now() + interval, interval: interval)
		} else {
			timer.scheduleOneshot(deadline: .now() + interval)
		}
		timer.setEventHandler(handler: completion)
		timer.resume()
	}

	func invalidate() {
		timer.cancel()
	}
}
