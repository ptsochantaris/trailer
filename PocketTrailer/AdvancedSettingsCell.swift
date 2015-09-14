import UIKit

final class AdvancedSettingsCell: UITableViewCell {
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var descriptionLabel: UILabel!
	@IBOutlet weak var valueLabel: UILabel!

	override func layoutSubviews() {
		super.layoutSubviews()
		for v in self.subviews {
			if let b = v as? UIButton {
				b.center = CGPointMake(b.center.x, valueLabel.center.y)
			}
		}
	}
}
