import Foundation

final class Timer {

	private let timer = DispatchSource.makeTimerSource(flags: [], queue: .main)

	init(repeats: Bool, interval: TimeInterval, block: @escaping () -> Void) {

		if repeats {
			timer.schedule(deadline: .now() + interval, repeating: interval)
		} else {
			timer.schedule(deadline: .now() + interval)
		}
		timer.setEventHandler(handler: block)
		timer.resume()
	}

	deinit {
		timer.cancel()
	}
}
