import UIKit

// with many thanks to https://github.com/davbeck/TUSafariActivity for the example and the icon

// Nonisolated to match `UIActivity`, which the SDK leaves unannotated. With MainActor default
// isolation these overrides would each be main-actor while the declaration they override is not,
// which Swift 6 rejects — and `@preconcurrency import UIKit` does *not* cover override mismatches,
// only Sendable ones. UIKit does call all of this on the main thread, so where a body genuinely needs
// main-actor state, the isolation is asserted rather than declared.
final nonisolated class OpenInSafariActivity: UIActivity {
    private var _URL: URL?

    override var activityType: UIActivity.ActivityType {
        UIActivity.ActivityType("OpenInSafariActivity")
    }

    override var activityTitle: String? {
        "Open in Safari"
    }

    override var activityImage: UIImage? {
        MainActor.assumeIsolated { .safariShare }
    }

    override func prepare(withActivityItems activityItems: [Any]) {
        for activityItem in activityItems {
            if let u = activityItem as? URL {
                _URL = u
                break
            }
        }
    }

    override func perform() {
        guard let url = _URL else { return }
        // `self` is a non-Sendable UIKit object, so it cannot be sent into the main-actor task that
        // performs the open. UIKit only ever drives a UIActivity from the main thread, so passing it
        // through explicitly is safe; doing it this way keeps the real completion result rather than
        // reporting success optimistically.
        nonisolated(unsafe) let activity = self
        Task { @MainActor in
            let success = await UIApplication.shared.open(url)
            activity.activityDidFinish(success)
        }
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
        // Narrow the items to something Sendable before crossing over, so `[Any]` stays on this side.
        let urls = activityItems.compactMap { $0 as? URL }
        return MainActor.assumeIsolated {
            urls.contains { UIApplication.shared.canOpenURL($0) }
        }
    }
}
