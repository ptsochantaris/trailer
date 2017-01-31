
import Foundation

final class PopTimer {

	private var popTimer: Timer?
	private let timeInterval: TimeInterval
	private let callback: Completion

	func push() {
		popTimer?.invalidate()
		popTimer = Timer(repeats: false, interval: timeInterval) { [weak self] in
			self?.invalidate()
			self?.callback()
		}
	}

	func invalidate() {
		popTimer?.invalidate()
		popTimer = nil
	}

	init(timeInterval: TimeInterval, callback: @escaping Completion) {
		self.timeInterval = timeInterval
		self.callback = callback
	}
}
