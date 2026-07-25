import Foundation
import Network

nonisolated enum NetworkStatus {
    case notReachable, reachableViaWiFi, reachableViaWWAN
    var name: String {
        switch self {
        case .notReachable:
            "Down"
        case .reachableViaWiFi:
            "Local"
        case .reachableViaWWAN:
            "Cellular"
        }
    }
}

let ReachabilityChangedNotification = Notification.Name("ReachabilityChangedNotification")

final class Reachability {
    private let monitor = NWPathMonitor()
    private var monitorTask: Task<Void, Never>?

    /// Polled synchronously by `API.hasNetworkConnection`, which deliberately re-reads the
    /// live state rather than trusting the last notification it received.
    ///
    /// This is not redundant: older macOS versions could fail to signal a network status
    /// change after waking from sleep, leaving a purely push-based value stale — which for
    /// this app means silently not syncing. That may well be fixed by now, but the failure
    /// is invisible when it happens, so the poll stays. Please don't "simplify" this into a
    /// cached property updated only by `startNotifier()`.
    var status: NetworkStatus {
        Reachability.status(for: monitor.currentPath)
    }

    func startNotifier() {
        guard monitorTask == nil else { return }

        // Iterate the same instance that `status` polls, so both see one started monitor.
        // Capturing the monitor rather than self also avoids a retain cycle.
        let monitor = monitor
        monitorTask = Task {
            var lastStatus: NetworkStatus?
            for await path in monitor {
                // NWPathMonitor reports interface-level changes that don't necessarily alter
                // reachability, so only announce when the derived status actually moves.
                // Observers treat every notification as a reason to consider refreshing.
                let newStatus = Reachability.status(for: path)
                if newStatus != lastStatus {
                    lastStatus = newStatus
                    NotificationCenter.default.post(name: ReachabilityChangedNotification, object: nil)
                }
            }
        }

        Task {
            await Logging.shared.log("Reachability monitoring active")
        }
    }

    deinit {
        monitorTask?.cancel()
    }

    private static func status(for path: NWPath) -> NetworkStatus {
        guard path.status == .satisfied else {
            return .notReachable
        }
        #if os(iOS)
            if path.usesInterfaceType(.cellular) {
                return .reachableViaWWAN
            }
        #endif
        return .reachableViaWiFi
    }
}
