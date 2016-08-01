
import UIKit

final class CountLabel: UILabel {

	override init(frame: CGRect) {
		super.init(frame: frame)
		isHidden = true
		layer.cornerRadius = 9
		clipsToBounds = true
		font = UIFont.systemFont(ofSize: 12)
		textAlignment = .center
		translatesAutoresizingMaskIntoConstraints = false
	}

	required init(coder aDecoder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: CGSize {
		var s = super.intrinsicContentSize
		s.height += 4
		s.width = max(s.height, s.width+9)
		return s
	}

}
