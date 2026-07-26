import UIKit

final class SectionHeaderView: UITableViewHeaderFooterView {
    @IBOutlet var title: UILabel!
    @IBOutlet var action: UIButton!

    var callback: (() -> Void)?

    @IBAction private func buttonSelected(_: UIButton) {
        callback?()
    }

    // `awakeFromNib` is nonisolated on NSObject, so the override has to be too — under MainActor
    // default isolation it would otherwise mismatch the declaration it overrides. Nib loading happens
    // on the main thread, so the isolation is asserted for the part that touches views.
    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            action.setTitleColor(UIColor(named: "apptint"), for: .normal)
        }
    }
}
