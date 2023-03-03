import Foundation

final actor Gate {
    let barrier = Barrier()
    var tickets: Int

    init(tickets: Int) {
        self.tickets = tickets
    }

    func takeTicket() async {
        await barrier.wait()
        tickets -= 1
        if tickets == 0 {
            await barrier.lock()
        }
    }

    func returnTicket() async {
        tickets += 1
        await barrier.unlock()
    }
    
    nonisolated func relaxedReturnTicket() {
        Task {
            await returnTicket()
        }
    }
}
