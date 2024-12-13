import Combine
import Foundation
import os.log

final actor Logging {
    static let shared = Logging()

    private let logPublisher = PassthroughSubject<() -> String, Never>()
    private var monitorObservation: Cancellable?

    var monitoringLog: Bool {
        consoleObservation != nil || monitorObservation != nil
    }

    func log(_ message: @Sendable @escaping @autoclosure () -> String) {
        if monitoringLog {
            logPublisher.send(message)
        }
    }

    private var consoleObservation: Cancellable?
    func setupConsoleLogging() {
        consoleObservation = logPublisher
            .sink { message in
                os_log("%{public}@", message())
            }
        log(">>> Will log to the system log, as '-useSystemLog' has been specified")
    }

    func setupMonitorCallback(_ block: (@MainActor (NSAttributedString) -> Void)?) {
        if let block {
            monitorObservation = logPublisher
                .sink { message in
                    let dateString = Date().formatted(Date.Formatters.logDateFormat)
                    #if canImport(AppKit)
                        let labelColor = COLOR_CLASS.labelColor
                    #else
                        let labelColor = COLOR_CLASS.label
                    #endif
                    let logString = NSAttributedString(string: ">>> \(dateString)\n\(message())\n\n", attributes: [.foregroundColor: labelColor])
                    Task { @MainActor in
                        block(logString)
                    }
                }
        } else {
            monitorObservation = nil
        }
    }
}
