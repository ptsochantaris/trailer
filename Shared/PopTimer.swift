
class PopTimer : NSObject {

	var _popTimer: NSTimer?
	let _timeInterval: NSTimeInterval
	let _callback: ()->()

	var isRunning: Bool {
		return _popTimer != nil
	}

	func push() {
		_popTimer?.invalidate()
		_popTimer = NSTimer.scheduledTimerWithTimeInterval(_timeInterval, target: self, selector: Selector("popped"), userInfo: nil, repeats: false)
	}

	func popped() {
		invalidate()
		_callback()
	}

	func invalidate() {
		_popTimer?.invalidate()
		_popTimer = nil
	}

	init(timeInterval: NSTimeInterval, callback: ()->Void) {
		_timeInterval = timeInterval
		_callback = callback
		super.init()
	}
}
