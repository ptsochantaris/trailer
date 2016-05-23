
import UIKit

final class CountLabel: UILabel {

	override init(frame: CGRect) {
		super.init(frame: frame)
		hidden = true
		layer.cornerRadius = 9
		clipsToBounds = true
		font = UIFont.systemFontOfSize(12)
		textAlignment = .Center
		translatesAutoresizingMaskIntoConstraints = false
	}

	required init(coder aDecoder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

    override func intrinsicContentSize() -> CGSize {
		var s = super.intrinsicContentSize()
		s.height += 4
		s.width = max(s.height, s.width+9)
		return s
	}

}
