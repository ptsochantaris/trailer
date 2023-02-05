import Foundation
import AsyncAlgorithms

public final class GateKeeper {
    private var channel: AsyncChannel<Void>
    private var iterator: AsyncChannel<Void>.Iterator
    
    public init(entries: Int) {
        channel = AsyncChannel<Void>()
        iterator = channel.makeAsyncIterator()
        Task {
            for _ in 0 ..< entries {
                await channel.send(())
            }
        }
    }

    public func waitForGate() async {
        _ = await iterator.next()
    }

    public func signalGate() {
        Task {
            await channel.send(())
        }
    }
}
