import Combine
import Foundation
import os.log

enum Logging {
    static let logPublisher = PassthroughSubject<() -> String, Never>()
    static var monitorObservation: Cancellable?

    static var monitoringLog: Bool {
        consoleObservation != nil || monitorObservation != nil
    }

    static func log(_ message: @escaping @autoclosure () -> String) {
        if monitoringLog {
            logPublisher.send(message)
        }
    }

    private static var consoleObservation: Cancellable?
    static func setupConsoleLogging() {
        consoleObservation = logPublisher
            .sink { message in
                os_log("%{public}@", message())
            }
        log(">>> Will log to the system log, as '-useSystemLog' has been specified")
    }
}
