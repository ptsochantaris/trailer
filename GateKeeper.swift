import Foundation
import AsyncAlgorithms

public final actor GateKeeper {
    private var stream = AsyncChannel<Void>()
    
    public init(entries: Int) {
        Task {
            for _ in 0 ..< entries {
                await stream.send(())
            }
        }
    }

    public func waitForGate() async {
        for await _ in stream {
            return
        }
    }

    public func signalGate() {
        Task {
            await stream.send(())
        }
    }
}
