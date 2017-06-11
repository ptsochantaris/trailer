
import Foundation

final class PopTimer {

	private var popTimer: Timer?
	private let timeInterval: TimeInterval
	private let callback: Completion

	func push() {
		popTimer = Timer(repeats: false, interval: timeInterval) { [weak self] in
			self?.abort()
			self?.callback()
		}
	}

	func abort() {
		popTimer = nil
	}

	var isRunning: Bool {
		return popTimer != nil
	}

	init(timeInterval: TimeInterval, callback: @escaping Completion) {
		self.timeInterval = timeInterval
		self.callback = callback
	}
}
