import AsyncAlgorithms

struct Gate {
    private let queue = AsyncChannel<Void>()

    init(tickets: Int) {
        for _ in 0 ..< tickets {
            returnTicket()
        }
    }

    func takeTicket() async {
        for await _ in queue {
            return
        }
    }

    func returnTicket() {
        Task {
            await queue.send(())
        }
    }
}
