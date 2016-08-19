
#if os(iOS)
	import UIKit
#endif

final class PopTimer {

	private var _popTimer: Timer?
	private let _timeInterval: TimeInterval
	private let _callback: () -> Void

	func push() {
		_popTimer?.invalidate()
		_popTimer = Timer.scheduledTimer(timeInterval: _timeInterval, target: self, selector: #selector(popped), userInfo: nil, repeats: false)
	}

	@objc
	func popped() {
		invalidate()
		_callback()
	}

	func invalidate() {
		_popTimer?.invalidate()
		_popTimer = nil
	}

	init(timeInterval: TimeInterval, callback: Completion) {
		_timeInterval = timeInterval
		_callback = callback
	}
}
