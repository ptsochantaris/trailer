import Combine
import Foundation

final class PopTimer {
    private let publisher = PassthroughSubject<Void, Never>()
    private let stride: RunLoop.SchedulerTimeType.Stride
    private let callback: () -> Void
    private var cancel: Cancellable?

    func push() {
        if cancel == nil {
            cancel = publisher.debounce(for: stride, scheduler: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                self.cancel = nil
                self.callback()
            }
        }
        publisher.send()
    }

    func abort() {
        if let c = cancel {
            c.cancel()
            cancel = nil
        }
    }

    var isPushed: Bool {
        cancel != nil
    }

    init(timeInterval: TimeInterval, callback: @escaping () -> Void) {
        self.stride = RunLoop.SchedulerTimeType.Stride(timeInterval)
        self.callback = callback
    }
}
