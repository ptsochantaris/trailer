import AsyncAlgorithms
import Foundation

final class GateKeeper {
    private var channel: AsyncChannel<Void>
    private var iterator: AsyncChannel<Void>.Iterator

    init(entries: Int) {
        channel = AsyncChannel<Void>()
        iterator = channel.makeAsyncIterator()
        Task {
            for _ in 0 ..< entries {
                await channel.send(())
            }
        }
    }

    func waitForGate() async {
        _ = await iterator.next()
    }

    func signalGate() {
        Task {
            await channel.send(())
        }
    }
}
