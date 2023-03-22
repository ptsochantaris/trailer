import Combine
import Foundation

public final actor Barrier {
    enum State {
        case locked, unlocked

        var immediateResult: Bool? {
            switch self {
            case .locked:
                return nil
            case .unlocked:
                return true
            }
        }
    }
    
    private let publisher = CurrentValueSubject<State, Never>(.unlocked)

    var state: State {
        publisher.value
    }
    
    func lock() {
        if publisher.value == .unlocked {
            publisher.send(.locked)
        }
    }

    func unlock() {
        if publisher.value == .locked {
            publisher.send(.unlocked)
        }
    }

    @discardableResult
    func wait() async -> Bool {
        if let result = publisher.value.immediateResult {
            return result
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            _ = publisher
                .handleEvents(receiveCancel: {
                    continuation.resume(returning: false)
                })
                .sink { value in
                    switch value {
                    case .locked:
                        break // shouldn't happen
                    case .unlocked:
                        continuation.resume(returning: true)
                    }
                }
        }
    }
}
