import Foundation
import AsyncAlgorithms

public final actor Gate {
    private let queue = AsyncChannel<Void>()

    public init(tickets: Int) {
        for _ in 0 ..< tickets {
            Task {
                await returnTicket()
            }
        }
    }

    public func takeTicket() async {
        for await _ in queue {
            return
        }
    }

    public func returnTicket() async {
        await queue.send(Void())
    }

    public nonisolated func relaxedReturnTicket() {
        Task {
            await returnTicket()
        }
    }
}
